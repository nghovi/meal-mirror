# Meal Mirror Privacy Site

This folder contains a standalone static privacy policy page for the Meal Mirror app.

## Files

- `index.html`: root redirect to `/privacy/`
- `privacy/index.html`: privacy policy page
- `styles.css`: page styling
- `httpd-ankieng.conf`: Apache virtual host config for `ankieng.truongdiem.online`

## Suggested publish target

- Site root: `/var/www/ankieng`
- Apache conf: `/etc/httpd/conf.d/ankieng.conf`

## Notes

- The Apache config serves the privacy page at `/privacy/` and redirects
  `/privacy` to `/privacy/`.
- The Apache config reuses the same TLS certificate files that `vieted` already
  installs on the server.
- If the server already has a wildcard certificate for `*.truongdiem.online`,
  no extra certificate work should be needed.
