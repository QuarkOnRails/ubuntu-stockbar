# stockbar

Stock prices in your Ubuntu top bar, either side of the clock, so you can watch your money and your time run out
together.

```
AAPL ▲ 1.23% $231.78   MSFT ▼ 0.41% $410.10   Oct 26  14:32   NVDA ▲ 2.07% $181.20   TSLA ▼ 3.12% $219.85
```

Click it and you get your whole watchlist, when it last updated, and a "Refresh now" button for when you can't wait
20 seconds to feel bad.

Stocks, indices, currencies, commodities, crypto. No account, no API key, no subscription, no "upgrade to Pro".

## Install

Ubuntu 22.04, 24.04, 26.04 or 26.10 with the regular GNOME desktop:

```sh
sudo add-apt-repository ppa:quarkonrails/stockbar
sudo apt install stockbar
```

On any other release, skip the PPA and [build it yourself](#building-it-yourself). The PPA has nothing for it and
`apt update` will complain.

Installing it doesn't switch anything on. Add your first stock (see below) and it turns itself on for your user.
Then **log out and back in once**. GNOME only notices new extensions at login, nobody can do anything about that.
stockbar keeps reminding you, in red, until you do.

After an update changes the extension, stockbar also reminds you to log out and back in to load it.
Updates that only change the CLI or background service do not trigger this notice.

## Getting started

Run

```sh
stockbar
```

and you get a little editor: search for stocks and add them, choose which ones sit in the top bar, reorder them, set
how often they refresh. Arrow keys and Enter, nothing to learn.

The first stock you add goes straight to the top bar. The rest wait in the dropdown until you pin them.

The top bar shows as many as fit: right of the clock first, then left of it. The rest hide behind a `…`,
the dropdown still has them all. An unusually long stock label is shortened to fit. Greed has limits, top bars more so.

## Commands

If you'd rather type than pick from menus:

```sh
stockbar add AAPL            # add by ticker
stockbar add "novo nordisk"  # or by name, you'll get a list to pick from
stockbar add TSLA --pin      # add it straight to the top bar
stockbar pin MSFT            # show it in the top bar
stockbar unpin MSFT          # back to the dropdown, out of sight, out of mind
stockbar remove MSFT         # out of your life entirely
stockbar list                # the whole watchlist with current prices
stockbar search apple        # find a ticker
stockbar refresh             # fetch prices now
stockbar interval 30         # refresh every 30 s (default 20, minimum 15)
stockbar scroll 5            # scroll the pinned stocks (1–10, slow to fast)
stockbar scroll 0            # stop scrolling (default)
stockbar status              # is it running, how old are the prices, what broke
stockbar disable             # turn it all off, your watchlist is kept
stockbar enable              # and back on
stockbar help
```

Scrolling moves the pinned stocks through the existing spaces beside the clock. Speeds 1–10 move at 8–80
logical pixels per second. The dropdown pauses scrolling while open. Changes apply when the daemon next writes
the quote cache. The interactive editor also has a scroll speed setting.

## Finding the right symbol

Prices come from CNBC, so symbols are CNBC's tickers. US stocks are what you'd expect (`AAPL`, `NVDA`), the rest
gets creative:

| You want      | Symbol    |
|---------------|-----------|
| SAP on XETRA  | `SAP-DE`  |
| S&P 500       | `.SPX`    |
| EUR/USD       | `EUR=`    |
| Bitcoin       | `BTC.CB=` |

You don't have to remember any of that. `stockbar search` finds things by name and knows what people usually call
them: `sp500`, `dow jones`, `dax`, `eurusd`, `gold`, `bitcoin`.

## When something looks wrong

Nothing in the top bar after installing? You haven't logged out and back in yet. Everyone skips that step.

Gone after upgrading Ubuntu? The upgrade switches PPAs off. Run `sudo add-apt-repository ppa:quarkonrails/stockbar`
again, then `sudo apt upgrade`.

If a price can't be fetched, the last known one stays in the bar, dimmed. Faded, like your hopes. Usually it's the
network or CNBC having a moment, and it sorts itself out on the next refresh.

`stockbar status` tells you whether the background service and the top bar extension are running and how old the
prices are. If that doesn't explain it, the logs might:

```sh
journalctl --user -u stockbar -f            # the service that fetches prices
journalctl --user -f /usr/bin/gnome-shell   # the top bar side
```

Still broken? [Open an issue](https://github.com/QuarkOnRails/ubuntu-stockbar/issues).

## Uninstall

```sh
stockbar disable
sudo apt remove stockbar
```

Your watchlist stays in `~/.config/stockbar/` in case you come crawling back. Delete it if you won't.

## Building it yourself

On another Ubuntu release (anything with GNOME 42 or newer), or rather not add a PPA? Build the package on the
machine you'll install it on:

```sh
git clone https://github.com/QuarkOnRails/ubuntu-stockbar.git
cd ubuntu-stockbar
sudo apt install dpkg-dev debhelper gnome-shell-common rake ruby ruby-minitest
dpkg-buildpackage -us -uc -b
sudo apt install ../stockbar_*_all.deb
```

For development, `rake test` runs the Ruby tests and `rake test_layout` checks pixel fitting with Node (no npm
dependencies). `python3 test/headless/run.py --size 1366x768` tests the extension in an isolated headless GNOME
session and saves screenshots and geometry under `build/headless/`. It also accepts `--scale 1.5` and `--rtl`.

## The fine print

Not financial advice. stockbar shows you numbers, what you do with them is between you and your broker.

Prices come from CNBC's public quote service. It's undocumented, so CNBC can change it whenever they feel like it,
and some markets may show delayed prices.

Looking at it more often won't make it go up. We checked.

MIT licensed, see [LICENSE](LICENSE).
