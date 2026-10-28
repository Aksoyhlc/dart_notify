/// SMTP encryption mode. [SmtpSecurity.startTlsRequired] requires STARTTLS and
/// fails the send when the server does not offer it.
enum SmtpSecurity { startTlsRequired, sslTls, none }
