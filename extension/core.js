// inlined into legacy.js / modern.js, which provide GLib, Gio, GObject, St, Clutter, Main,
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

// what the panel lays out for each half. both are as wide as the wider half so the clock between them stays
// centred, and the narrower half's spare room is outside its button, not in its hover highlight
const StockbarSlot = GObject.registerClass(
class StockbarSlot extends St.Bin {
    // 0 while the half is hidden
    _ownWidth() {
        return super.vfunc_get_preferred_width(-1);
    }

    vfunc_get_preferred_width(forHeight) {
        const [min, nat] = super.vfunc_get_preferred_width(forHeight);
        return [min, Math.max(nat, this.twin?._ownWidth()[1] ?? 0)];
    }
});

// one side of the clock, with the whole watchlist in its dropdown
const StockbarIndicator = GObject.registerClass(
class StockbarIndicator extends PanelMenu.Button {
    _init(side, onRefresh) {
        super._init(0.5, 'Stockbar', false);
        // ButtonBox wraps every panel button in a plain St.Bin and destroys whatever this.container is
        this.container.child = null;
        this.container.destroy();
        this.container = new StockbarSlot({child: this});
        // hug the clock
        this.x_align = side === 'left' ? Clutter.ActorAlign.END : Clutter.ActorAlign.START;
        this._onRefresh = onRefresh;

        this._box = new St.BoxLayout({style_class: 'panel-status-menu-box stockbar-box'});
        this.add_child(this._box);
    }

    rebuildMenu(data) {
        this.menu.removeAll();
        const items = data?.items ?? [];
        if (items.length === 0) {
            const hint = data ? 'Your watchlist is empty.' : 'No quotes yet.';
            this.menu.addMenuItem(new PopupMenu.PopupMenuItem(`${hint} Run “stockbar” in a terminal to add stocks.`,
                {reactive: false}));
        }
        for (const item of items)
            this.menu.addMenuItem(this._stockRow(item));

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._statusItem = new PopupMenu.PopupMenuItem('', {reactive: false, style_class: 'stockbar-status'});
        this.menu.addMenuItem(this._statusItem);
        const refresh = new PopupMenu.PopupMenuItem('Refresh now');
        refresh.connect('activate', () => this._onRefresh());
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

    setStatus(text, stale) {
        this._box.opacity = stale ? STALE_OPACITY : 255;
        this._statusItem.label.text = text;
    }
});

// watches the daemon's cache and feeds both halves
class Stockbar {
    constructor(uuid) {
        const requestRefresh = () => this._requestRefresh();
        const [left, right] = this._halves = [
            new StockbarIndicator('left', requestRefresh),
            new StockbarIndicator('right', requestRefresh),
        ];
        left.container.twin = right.container;
        right.container.twin = left.container;
        this._debounceId = 0;
        this._fitId = 0;
        this._fitting = false;

        const clock = Main.panel.statusArea.dateMenu.container;
        const index = clock.get_parent().get_children().indexOf(clock);
        const rtl = Main.panel.get_text_direction() === Clutter.TextDirection.RTL;
        Main.panel.addToStatusArea(`${uuid}-left`, left, index, 'center');
        Main.panel.addToStatusArea(`${uuid}-right`, right, index + 2, 'center');
        if (rtl) {
            Main.panel._centerBox.set_child_at_index(right.container, index);
            Main.panel._centerBox.set_child_at_index(left.container, index + 2);
        }
        // set direction after insertion, which inherits the panel's direction
        for (const half of this._halves)
            half.container.set_text_direction(Clutter.TextDirection.LTR);
        this._panelActors = [Main.panel, Main.panel._leftBox, Main.panel._centerBox, Main.panel._rightBox];
        for (const actor of this._panelActors) {
            actor.connectObject('notify::allocation', () => this._scheduleFit(),
                // contents can grow without changing a constrained box's allocation
                'queue-relayout', () => this._scheduleFit(),
                'style-changed', () => this._scheduleFit(), this);
        }
        global.display.connectObject('workareas-changed', () => this._scheduleFit(), this);
        Main.layoutManager.connectObject('monitors-changed', () => this._scheduleFit(), this);

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
        for (const half of this._halves)
            half.rebuildMenu(this._data);
        this._updateStaleness();
    }

    _isStale() {
        const maxAge = Math.max(3 * this._data.refresh_interval, MIN_STALE_SECONDS);
        return Date.now() / 1000 - this._data.updated_at_epoch > maxAge;
    }

    _rebuildBar() {
        const anchor = this._scroll?.anchor();
        this._scroll?.destroy();
        this._scroll = null;
        for (const half of this._halves)
            half._box.destroy_all_children();
        const items = (this._data?.items ?? []).filter(item => item.pinned);
        const speed = this._data?.scroll_speed ?? 0;
        if (speed > 0 && items.length > 0) {
            this._scroll = new StockbarScroll(this._halves, items, speed, anchor);
            this._fit();
            return;
        }
        this._labels = items.map(item =>
            createLabel(item.bar_text, `stockbar-label ${directionClass(item)}`, item.stale));
        if (items.length === 0)
            this._labels.push(createLabel('Stocks', 'stockbar-label'));
        this._moreLabel = createLabel('…', 'stockbar-label');
        // keep hidden labels on stage so they inherit font changes
        for (const label of [...this._labels, this._moreLabel]) {
            this._halves[1]._box.add_child(label);
            label.hide();
        }
        this._lastFit = null;
        this._fit();
    }

    _scheduleFit() {
        if (this._fitId || this._fitting)
            return;
        this._fitId = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._fitId = 0;
            this._fit();
            return GLib.SOURCE_REMOVE;
        });
    }

    _sideRoom() {
        const panel = Main.panel;
        const monitor = Main.layoutManager.findMonitorForActor(panel);
        if (!monitor || panel.width <= 0)
            return 0;
        const workArea = Main.layoutManager.getWorkAreaForMonitor(monitor.index);
        // match Panel.vfunc_allocate without feeding rounded allocations back into the fit
        const offset = 2 * (workArea.x - monitor.x) + workArea.width - monitor.width;
        const midpoint = (panel.width + offset) / 2;
        const natural = actor => actor.get_preferred_width(-1)[1];
        const [left, right] = this._halves;
        const others = natural(panel._centerBox) - natural(left.container) - natural(right.container);
        const padding = Math.max(...this._halves.map(half => natural(half) - natural(half._box)));
        const rtl = panel.get_text_direction() === Clutter.TextDirection.RTL;
        const leftWidth = natural(rtl ? panel._rightBox : panel._leftBox);
        const rightWidth = natural(rtl ? panel._leftBox : panel._rightBox);
        return sideRoom(panel.width, midpoint, leftWidth, rightWidth, others, padding);
    }

    _fit() {
        this._fitting = true;
        try {
            if (this._scroll)
                this._scroll.fit(this._sideRoom());
            else
                this._applyFit();
        } finally {
            this._fitting = false;
        }
    }

    _applyFit() {
        const [left, right] = this._halves;
        const measure = label => {
            label.ensure_style();
            // measure the full text, ignoring the label's cut width
            return label.clutter_text.get_preferred_width(-1)[1];
        };
        const widths = this._labels.map(measure);
        const moreWidth = measure(this._moreLabel);
        const spacing = Math.max(...this._halves.map(half => half._box.get_theme_node().get_length('spacing')));
        const fit = fitStocks(widths, this._sideRoom(), spacing, moreWidth);
        const key = JSON.stringify(fit);
        if (key === this._lastFit)
            return;
        this._lastFit = key;

        for (const label of [...this._labels, this._moreLabel])
            label.get_parent().remove_child(label);
        this._labels.forEach((label, i) => {
            const half = i < fit.onRight ? right : left;
            half._box.add_child(label);
            label.width = i < fit.shown ? fit.widths[i] : -1;
            label.visible = i < fit.shown;
        });
        right._box.add_child(this._moreLabel);
        this._moreLabel.visible = fit.more;
        left.visible = fit.shown > fit.onRight;
        right.visible = fit.onRight > 0 || fit.more;
        // the unchanged twin also needs to recalculate its width
        for (const half of this._halves)
            half.container.queue_relayout();
    }

    _updateStaleness() {
        const data = this._data;
        const stale = data && this._isStale();

        let text;
        if (!data)
            text = 'Waiting for the stockbar service…';
        else if (stale)
            text = `⚠ Not updated since ${data.updated_at_text}. Is ${SERVICE} running?`;
        else
            text = `Updated ${data.updated_at_text}${data.error ? ` · ⚠ ${data.error}` : ''}`;
        for (const half of this._halves)
            half.setStatus(text, stale);
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
        this._scroll?.destroy();
        for (const actor of this._panelActors)
            actor.disconnectObject(this);
        global.display.disconnectObject(this);
        Main.layoutManager.disconnectObject(this);
        if (this._fitId)
            GLib.source_remove(this._fitId);
        if (this._debounceId)
            GLib.source_remove(this._debounceId);
        GLib.source_remove(this._staleId);
        this._monitor.disconnect(this._monitorId);
        this._monitor.cancel();
        // a half being torn down shouldn't be asked for its width
        for (const half of this._halves)
            half.container.twin = null;
        for (const half of this._halves)
            half.destroy();
    }
}
