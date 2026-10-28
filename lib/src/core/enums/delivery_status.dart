/// Upstream acceptance by an API or SMTP server does not mean the message
/// reached a device or inbox.
enum DeliveryStatus { accepted, partiallyAccepted, skipped, failed, unknown }
