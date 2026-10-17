// inlined into legacy.js / modern.js, which provide GLib, Gio, GObject, St, Clutter,
// PanelMenu and PopupMenu. no import/export in here

const CACHE_NAME = 'quotes.json';
const CACHE_DIR = GLib.build_filenamev([GLib.get_user_cache_dir(), 'stockbar']);
const SERVICE = 'stockbar.service';
const STALE_CHECK_SECONDS = 30;
// one rename fires several monitor events
const DEBOUNCE_MS = 250;
// the daemon writes every refresh_interval and retries a failed round after 60 s, older data means it stopped
const MIN_STALE_SECONDS = 3 * 60;
const STALE_OPACITY = 128;

function readCache() {
    try {
        const [, bytes] = GLib.file_get_contents(GLib.build_filenamev([CACHE_DIR, CACHE_NAME]));
        return JSON.parse(new TextDecoder().decode(bytes));
    } catch {
        return null;
    }
}

function directionClass(item) {
    return `stockbar-${item.direction}`;
}

function createLabel(text, styleClass, stale = false, props = {}) {
    const label = new St.Label({text, style_class: styleClass, y_align: Clutter.ActorAlign.CENTER, ...props});
    if (stale)
        label.opacity = STALE_OPACITY;
    return label;
}

const StockbarIndicator = GObject.registerClass(
class StockbarIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Stockbar', false);

        this._box = new St.BoxLayout({style_class: 'panel-status-menu-box stockbar-box'});
        this.add_child(this._box);
        this._debounceId = 0;

        this._reload();
        this._watch();
        this._staleId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, STALE_CHECK_SECONDS, () => {
            this._updateStaleness();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _watch() {
        // monitoring needs the directory, which the daemon only creates on its first write
        GLib.mkdir_with_parents(CACHE_DIR, 0o777);
        // the daemon renames a temp file over quotes.json, so watch the directory
        this._monitor = Gio.File.new_for_path(CACHE_DIR).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitorId = this._monitor.connect('changed', (_monitor, file, otherFile) => {
            if ([file, otherFile].some(f => f?.get_basename() === CACHE_NAME))
                this._scheduleReload();
        });
    }

    _scheduleReload() {
        if (this._debounceId)
            return;
        this._debounceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, DEBOUNCE_MS, () => {
            this._debounceId = 0;
            this._reload();
            return GLib.SOURCE_REMOVE;
        });
    }

    _reload() {
        this._data = readCache();
        this._rebuildBar();
        this._rebuildMenu();
        this._updateStaleness();
    }

    _items() {
        return this._data?.items ?? [];
    }

    _isStale() {
        const maxAge = Math.max(3 * this._data.refresh_interval, MIN_STALE_SECONDS);
        return Date.now() / 1000 - this._data.updated_at_epoch > maxAge;
    }

    _rebuildBar() {
        this._box.destroy_all_children();
        const pinned = this._items().filter(item => item.pinned);
        if (pinned.length === 0)
            this._box.add_child(createLabel('Stocks', 'stockbar-label'));
        for (const item of pinned)
            this._box.add_child(createLabel(item.bar_text, `stockbar-label ${directionClass(item)}`, item.stale));
    }

    _rebuildMenu() {
        this.menu.removeAll();
        const items = this._items();
        if (items.length === 0) {
            const hint = this._data ? 'Your watchlist is empty.' : 'No quotes yet.';
            this.menu.addMenuItem(new PopupMenu.PopupMenuItem(`${hint} Run “stockbar” in a terminal to add stocks.`,
                {reactive: false}));
        }
        for (const item of items)
            this.menu.addMenuItem(this._stockRow(item));

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._statusItem = new PopupMenu.PopupMenuItem('', {reactive: false, style_class: 'stockbar-status'});
        this.menu.addMenuItem(this._statusItem);
        const refresh = new PopupMenu.PopupMenuItem('Refresh now');
        refresh.connect('activate', () => this._requestRefresh());
        this.menu.addMenuItem(refresh);
    }

    _stockRow(item) {
        // reactive: false would grey the row out as insensitive, activate: false just keeps it inert
        const row = new PopupMenu.PopupBaseMenuItem({
            activate: false,
            hover: false,
            can_focus: false,
            style_class: 'stockbar-row',
        });
        row.add_child(createLabel(item.display_symbol, 'stockbar-menu-symbol', item.stale));
        row.add_child(createLabel(item.name, 'stockbar-menu-name', item.stale, {x_expand: true}));
        row.add_child(createLabel(item.change_text ?? 'no data', `stockbar-menu-change ${directionClass(item)}`,
            item.stale));
        row.add_child(createLabel(item.price_text ?? '–', 'stockbar-menu-price', item.stale));
        return row;
    }

    _updateStaleness() {
        const data = this._data;
        const stale = data && this._isStale();
        this._box.opacity = stale ? STALE_OPACITY : 255;

        let text;
        if (!data)
            text = 'Waiting for the stockbar service…';
        else if (stale)
            text = `⚠ Not updated since ${data.updated_at_text}. Is ${SERVICE} running?`;
        else
            text = `Updated ${data.updated_at_text}${data.error ? ` · ⚠ ${data.error}` : ''}`;
        this._statusItem.label.text = text;
    }

    // going through systemctl keeps ruby (and rvm's PATH) out of the shell process
    _requestRefresh() {
        try {
            const proc = Gio.Subprocess.new(['systemctl', '--user', 'kill', '--signal=USR1', SERVICE],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
            proc.wait_check_async(null, (p, result) => {
                try {
                    p.wait_check_finish(result);
                } catch (e) {
                    logError(e, `stockbar: is ${SERVICE} running?`);
                }
            });
        } catch (e) {
            logError(e, 'stockbar');
        }
    }

    destroy() {
        if (this._debounceId)
            GLib.source_remove(this._debounceId);
        GLib.source_remove(this._staleId);
        this._monitor.disconnect(this._monitorId);
        this._monitor.cancel();
        super.destroy();
    }
});
