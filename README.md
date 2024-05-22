# Communication Platform

A small Sinatra service that sends transactional email through SendGrid, falls back to Postmark when SendGrid is down or rejects the request, and records every sent email and every provider webhook event in PostgreSQL.

Callers get one endpoint and one JSON contract. We decide which provider handles each email, so a SendGrid outage doesn't become an outage for whoever is sending mail.

## How a request flows

```mermaid
flowchart LR
    client([Client]) -->|POST /email| app[CommunicationApp]
    app -->|validate| model[Email model]
    model -->|1st choice| sg[SendGrid v3 mail/send]
    model -.->|on error, timeout or missing key| pm[Postmark /email]
    model -->|first 2xx wins| db[(PostgreSQL: emails)]
    sg -.->|event webhook| hooks[/sg_webhook/]
    pm -.->|event webhook| hooks2[/pm_webhook/]
    hooks --> logs[(webhook_logs)]
    hooks2 --> logs
```

1. The request body (JSON or form-encoded) is checked against the allowed attributes. Unknown keys, including internal columns such as `service` or `status`, are rejected with 422.
2. The `Email` model validates the addresses and required fields.
3. Providers are tried in the order set in `Email::DELIVERY_SERVICES` (SendGrid, then Postmark). A provider is skipped when its API key is blank. A non-2xx answer, a timeout (5 s to connect, 15 s to read) or a refused connection moves on to the next provider.
4. The first provider that accepts the email is stored with the email, together with its HTTP status and response body. If every provider fails, nothing is stored and the endpoint answers 503.

## Running it

### With Docker Compose (recommended)

```sh
cp .env.example .env      # add SG_KEY and/or POSTMARK_TOKEN
docker compose up --build
```

The app listens on `http://localhost:4567`. On start, the container creates and migrates the `email_communication_production` database in the bundled PostgreSQL 17 service. Compose sets the database connection itself, so you only need to fill in the provider keys in `.env`. If both keys are blank, every send answers 503.

### Without Docker

You need Ruby 3.4.12 (see `.ruby-version`) and a running PostgreSQL.

```sh
cp .env.example .env      # set db_* and provider keys
bundle install
bundle exec rake db:create db:migrate
bundle exec rackup -p 4567
```

### Configuration

| Variable | Purpose |
| --- | --- |
| `SG_KEY` | SendGrid API key. Leave blank to skip SendGrid. |
| `POSTMARK_TOKEN` | Postmark server token. Leave blank to skip Postmark. |
| `db_host`, `db_port`, `db_username`, `db_password` | PostgreSQL connection (`db_name` overrides the production database name). |
| `WEBHOOK_USERNAME`, `WEBHOOK_PASSWORD` | When both are set, the webhook endpoints require HTTP basic auth. Both providers can call a URL such as `https://hooks:secret@example.com/sg_webhook`. |
| `SENDGRID_API_URL`, `POSTMARK_API_URL` | Override the provider endpoints, for example to point at a local fake. |

## API

All responses are JSON in the form `{ "status": <code>, "message": ... }`, and the HTTP status matches `status`. The one exception is a successful send: the HTTP status is 201 and `status` holds the provider's own status code. The examples below were captured from the Compose stack, with both providers replaced by a local fake.

### `POST /email`

| Attribute | Required | Notes |
| --- | --- | --- |
| `to`, `to_name` | yes | Recipient address and display name |
| `from`, `from_name` | yes | Sender address and display name. The address must be a verified sender with your provider. |
| `subject` | yes | |
| `body` | yes | Sent as HTML |
| `send_at` | no | Schedules the email. Accepts `DD MM YYYY HH:MM:SS +HH:MM` (e.g. `23 12 2026 09:00:00 +00:00`) or ISO 8601. |

```sh
curl -i http://localhost:4567/email -H 'Content-Type: application/json' -d '{
  "to": "ada@example.com", "to_name": "Ada Lovelace",
  "from": "relay@example.com", "from_name": "Relay Demo",
  "subject": "Welcome aboard", "body": "<p>Hi Ada</p>"
}'
```

```http
HTTP/1.1 201 Created
content-type: application/json

{"status":202,"message":"Success","id":1,"service":"sendgrid"}
```

When SendGrid answered 500, the same request went to Postmark:

```http
HTTP/1.1 201 Created

{"status":200,"message":"Success","id":3,"service":"postmark"}
```

Validation errors use Active Model's error details:

```sh
curl -i http://localhost:4567/email -H 'Content-Type: application/json' \
  -d '{"to":"not-an-address","subject":"Hi"}'
```

```http
HTTP/1.1 422 Unprocessable Content

{"status":422,"message":{"from":[{"error":"blank"},{"error":"invalid","value":null}],"body":[{"error":"blank"}],"to_name":[{"error":"blank"}],"from_name":[{"error":"blank"}],"to":[{"error":"invalid","value":"not-an-address"}]}}
```

Other failures:

| HTTP | When |
| --- | --- |
| 400 | The body is malformed JSON |
| 422 | An attribute is missing or invalid, an unknown attribute was sent, or `send_at` could not be read |
| 503 | Every provider failed: `"Email services are down or configured incorrectly"` |
| 500 | Unexpected error. The message is always `"Internal server error"`, and details go to the server log. |

#### Scheduled delivery

Postmark has no scheduled sending. We confirmed this in their documentation and with their support, so scheduled emails go only to SendGrid, which receives `send_at` as a Unix timestamp. If SendGrid can't take a scheduled email, the request fails with 503 rather than being sent immediately through Postmark. SendGrid accepts schedules up to 72 hours ahead.

### `POST /sg_webhook` and `POST /pm_webhook`

Point the SendGrid Event Webhook at `/sg_webhook` and the Postmark webhooks at `/pm_webhook`. Each event is stored in `webhook_logs` with the provider, the event type, the recipient address and the full payload. SendGrid sends events in batches, and every event in the batch is logged.

```sh
curl -i http://localhost:4567/sg_webhook -H 'Content-Type: application/json' -d '[
  {"email":"ada@example.com","event":"processed","sg_message_id":"m1"},
  {"email":"ada@example.com","event":"delivered","sg_message_id":"m1"}
]'
```

```http
HTTP/1.1 200 OK

{"status":200,"logged":2}
```

Postmark bounce and spam-complaint events name the address `Email`, while delivery, open and click events name it `Recipient`. Both are read:

```sh
curl -i http://localhost:4567/pm_webhook -H 'Content-Type: application/json' \
  -d '{"RecordType":"Delivery","Recipient":"ada@example.com","MessageID":"b7bc2f4a-e38e-4336-af7d-e6c392c2f817"}'
```

```http
HTTP/1.1 200 OK

{"status":200,"logged":1}
```

Events without a valid address are skipped and not counted in `logged`.

## Tests

The RSpec suite never contacts SendGrid or Postmark. WebMock blocks outgoing HTTP and stubs both APIs, and the specs set fake keys before `.env` is loaded. The suite covers the provider order, failover on errors and timeouts, scheduling, attribute filtering, the error codes, both webhooks and the basic-auth check.

```sh
docker compose --profile test run --rm test
```

Or locally, against your own PostgreSQL:

```sh
bundle exec rake db:create db:schema:load RACK_ENV=test
bundle exec rspec
```

## Project layout

```
communication_app.rb        routes, payload parsing, webhook auth
models/email.rb             validation, provider order, delivery
models/webhook_log.rb       stored webhook events
lib/email_services/         one small client per provider + shared HTTP helper
config/                     boot file and database.yml
db/                         migrations and schema
spec/                       request, model and client specs
```

## Design notes

- **Deliver, then save.** The email is validated, sent and only then written, so no HTTP call runs inside a database transaction. Failed attempts leave no row behind.
- **Plain `Net::HTTP` instead of the provider SDKs.** Each provider takes one JSON POST, so there is no SDK dependency to keep up to date. Adding a third provider means one small class and one entry in `Email::DELIVERY_SERVICES`.
- **Explicit attribute list.** Request attributes are filtered against `Email::REQUEST_ATTRIBUTES`, so a client can't write the `service`, `status` or `api_response` columns.

## License

MIT, see [LICENSE](LICENSE).
