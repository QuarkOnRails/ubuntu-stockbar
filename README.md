# stockbar

Stock quotes in the GNOME top bar (Ubuntu 22.04 / 24.04 / 26.04), managed from a Ruby CLI.

```
AAPL ▲ 1.23% $231.78   MSFT ▼ 0.41% $410.10        ← pinned stocks, in the top bar
```

Clicking it opens a dropdown with every stock in the watchlist, when it last updated, and "Refresh now".

## Install

Build the package on the Ubuntu release you install it on. The build picks the extension variant for that
release's GNOME (42–44 or 45+).

```sh
sudo apt install dpkg-dev debhelper gnome-shell-common rake ruby ruby-minitest
dpkg-buildpackage -us -uc -b
sudo apt install ../stockbar_0.1.0_all.deb
```

The package turns nothing on for anyone. Your first watchlist change (or starting `stockbar`) enables the extension
and the background service for your user. Then log out and back in once: on Wayland, GNOME Shell only picks up new
extensions at login. `stockbar enable` / `stockbar disable` do it by hand.

## Usage

```sh
stockbar                     # interactive editor: add (search), remove, choose top-bar stocks, reorder, interval
stockbar search apple
stockbar add AAPL --pin      # a ticker is added directly
stockbar add "novo nordisk"  # anything else offers search results to pick from
stockbar pin MSFT / unpin MSFT
stockbar remove MSFT
stockbar list                # table with current prices
stockbar refresh             # fetch now instead of waiting for the next round
stockbar interval 30         # refresh every 30 s (minimum 15), without a number it shows the current one
stockbar status              # service, extension, data age, last errors
stockbar disable             # extension and service off, the watchlist stays
```

Symbols are CNBC tickers: `AAPL`, `SAP-DE` (XETRA), `.SPX` (S&P 500), `EUR=` (EUR/USD), `BTC.CB=` (Bitcoin).
`stockbar search` finds them by name. The top bar shows CNBC's short names, e.g. "S&P 500" for `.SPX`.

The first stock you add is pinned automatically. The refresh interval can also be set in the interactive editor or
as `refresh_interval` in `~/.config/stockbar/config.json`.

Logs: `journalctl --user -u stockbar -f`. GNOME side: `journalctl --user -f /usr/bin/gnome-shell`
(or `journalctl /usr/bin/gnome-shell -f`).

## How it fits together

- `stockbar` (Ruby) keeps the watchlist in `~/.config/stockbar/config.json`.
- `stockbar.service` (systemd user unit) runs `stockbar daemon`. It fetches quotes every 20 s and writes ready-made
  text to `~/.cache/stockbar/quotes.json`.
- The GNOME extension `stockbar@quarkonrails.github.io` (JS, because GNOME Shell only runs JS) watches that file and
  draws it. It has no fetching logic, "Refresh now" just signals the service.

Quotes come from CNBC's quote service and need no API key: one request per round fetches the whole watchlist. The
service is public but undocumented, so it can change without notice. If a fetch fails, the last known price stays
visible, dimmed.

`/usr/bin/stockbar` runs the system Ruby with rvm, rbenv and bundler variables cleared. Everything except the
interactive editor is stdlib-only. The editor's gems (tty-prompt and friends) ship in `third_party/`, because Ubuntu
22.04's own `ruby-tty-prompt` breaks on Ruby 3.

## Development

```sh
bundle install           # minitest and rake into vendor/bundle (or: sudo apt install rake ruby-minitest)
bundle exec rake test    # offline: CNBC parsing, formatting, config, cache, setup, CLI, tty-prompt
```

Running from a checkout without the package:

```sh
rake extension GNOME_MAJOR=46   # your GNOME version, see gnome-shell --version
cp -r build/gnome-shell/extensions/stockbar@quarkonrails.github.io ~/.local/share/gnome-shell/extensions/
bin/stockbar daemon             # stands in for the service
```

`extension/core.js` is shared. `legacy.js` (GNOME 42–44, `imports.*`) and `modern.js` (GNOME 45+, ES modules) are
thin wrappers that `rake extension` joins with it at the `//@@CORE@@` line.

## License

MIT, see [LICENSE](LICENSE). The bundled gems in `third_party/` are MIT too, see `debian/copyright`.
