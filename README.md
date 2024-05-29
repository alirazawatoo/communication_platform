# Communication Platform

A Sinatra email-delivery service that validates a message, attempts SendGrid first, and falls back to Postmark when immediate delivery fails. Successful provider responses are recorded in PostgreSQL, while SendGrid and Postmark webhook events are stored separately for later inspection.

## Delivery sequence

```text
POST /email
    |
    v
validate recipient, sender, subject, and body
    |
    v
SendGrid request ---- success ----> store provider response
    |
    | failure
    v
Postmark request ---- success ----> store provider response
    |
    | failure
    v
raise service failure
```

Scheduled delivery uses SendGrid only because the Postmark adapter intentionally skips messages with `send_at`.

## API

### Send an email

```http
POST /email
Content-Type: application/json

{
  "to": "recipient@example.com",
  "to_name": "Recipient",
  "from": "sender@example.com",
  "from_name": "Sender",
  "subject": "Status update",
  "body": "<p>Your report is ready.</p>"
}
```

An optional `send_at` value is parsed as a timestamp and passed to SendGrid.

### Provider webhooks

- `POST /sg_webhook` stores the first SendGrid event in the submitted array.
- `POST /pm_webhook` stores a Postmark event using its record type and email.

## Local setup

```bash
git clone https://github.com/alirazawatoo/communication_platform.git
cd communication_platform
bundle install
cp .env.example .env
bundle exec rake db:create db:migrate
bundle exec rackup
```

Local environment values are required for PostgreSQL, SendGrid, Postmark, registered senders, and test recipients. Never commit real provider credentials.

## Tests

```bash
RACK_ENV=test bundle exec rake db:create db:migrate
bundle exec rspec
```

The RSpec suite covers email validation and endpoint behavior and uses VCR/WebMock around provider calls. It was inspected but not executed during this review.

## Failure semantics and boundaries

- Email delivery happens in an ActiveRecord `after_create` callback, coupling database persistence to external network calls.
- If both providers fail, a broad exception is raised after the record has entered the save lifecycle.
- Only successful provider selection is written to the email record; failed attempts are not modeled as separate delivery attempts.
- The endpoint and webhook routes have no authentication or provider-signature verification.
- Requests use `Net::HTTP.post` without explicit connect/read timeouts.
- Provider retry, idempotency, duplicate-webhook, and background-delivery semantics are not implemented.

## Next improvements

1. Persist a delivery request, then process provider attempts in a background job.
2. Record each attempt with provider, timing, response, and terminal state.
3. Add timeouts, bounded retries, idempotency keys, and circuit-breaker behavior.
4. Verify webhook signatures and authenticate message submission.
5. Add deterministic failover tests that do not require live provider credentials.
