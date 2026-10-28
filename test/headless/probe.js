// test extension, wrapped for the installed shell by run.py
const UUID = 'stockbar@quarkonrails.github.io';
let timer = 0;
let settleId = 0;
let busy = false;
let dummy = null;
let fits = 0;
let watched = null;
let originalFit = null;

function controller() {
    const stockbar = Main.extensionManager.lookup(UUID)?.stateObj?._stockbar;
    if (stockbar && watched !== stockbar) {
        watched = stockbar;
        originalFit = stockbar._fit;
        stockbar._fit = function () {
            fits++;
            return originalFit.call(this);
        };
    }
    return stockbar;
}

function span(actor) {
    const box = actor.get_allocation_box();
    let x = box.x1;
    for (let parent = actor.get_parent(); parent && parent !== Main.panel; parent = parent.get_parent())
        x += parent.get_allocation_box().x1;
    return [x, x + box.x2 - box.x1];
}

function geometry() {
    const stockbar = controller();
    if (!stockbar)
        return {enabled: false};
    const boxes = {};
    for (const side of ['left', 'center', 'right']) {
        const box = Main.panel[`_${side}Box`];
        boxes[side] = {span: span(box), natural: box.get_preferred_width(-1)[1]};
    }
    return {
        enabled: true,
        width: Main.panel.width,
        rtl: Main.panel.get_text_direction() === Clutter.TextDirection.RTL,
        boxes,
        clock: span(Main.panel.statusArea.dateMenu.container),
        halves: stockbar._halves.map(half => ({
            slot: span(half.container),
            visible: half.visible,
            labels: half._box.get_children().filter(label => label.visible).map(label => ({
                text: label.text, span: span(label), width: label.width,
                fullWidth: label.clutter_text.get_preferred_width(-1)[1],
            })),
        })),
        fit: JSON.parse(stockbar._lastFit),
        room: stockbar._sideRoom(),
        quote: stockbar._data?.updated_at_epoch,
        fits,
    };
}

function settledGeometry(request) {
    const deadline = GLib.get_monotonic_time() + 20 * GLib.USEC_PER_SEC;
    let previous = null;
    let unchanged = 0;
    return new Promise((resolve, reject) => {
        settleId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
            try {
                if (GLib.get_monotonic_time() >= deadline)
                    throw new Error(`panel did not settle for ${request.id}`);
                const stockbar = controller();
                const ready = request.action === 'disable' ? !stockbar :
                    stockbar && stockbar._data?.updated_at_epoch === request.quote &&
                    !stockbar._debounceId && !stockbar._fitId && Main.panel.has_allocation();
                if (Main.layoutManager._startingUp || !ready) {
                    unchanged = 0;
                    return GLib.SOURCE_CONTINUE;
                }
                const result = geometry();
                const key = JSON.stringify(result);
                unchanged = key === previous ? unchanged + 1 : 0;
                previous = key;
                if (unchanged < 2)
                    return GLib.SOURCE_CONTINUE;
                resolve(result);
            } catch (error) {
                reject(error);
            }
            settleId = 0;
            return GLib.SOURCE_REMOVE;
        });
    });
}

async function handle(dir, request) {
    if (request.action === 'tray') {
        if (!dummy) {
            dummy = new St.Widget({height: 20});
            Main.panel._rightBox.add_child(dummy);
        }
        dummy.width = request.width;
    } else if (request.action === 'remove-tray') {
        dummy?.destroy();
        dummy = null;
    } else if (request.action === 'disable') {
        controller()?._scheduleFit();
        Main.extensionManager.disableExtension(UUID);
    } else if (request.action === 'enable') {
        Main.extensionManager.enableExtension(UUID);
    } else if (request.action === 'text-scale') {
        new Gio.Settings({schema_id: 'org.gnome.desktop.interface'}).set_double('text-scaling-factor', request.scale);
    }
    const result = await settledGeometry(request);
    if (request.screenshot) {
        const stream = Gio.File.new_for_path(`${dir}/${request.id}.png`).replace(
            null, false, Gio.FileCreateFlags.NONE, null);
        await new Shell.Screenshot().screenshot_area(0, 0, Main.panel.width, Main.panel.height, stream);
        stream.close(null);
    }
    GLib.file_set_contents(`${dir}/${request.id}.json`, JSON.stringify(result));
}

function enableProbe() {
    const dir = GLib.getenv('STOCKBAR_PROBE_DIR');
    // force RTL without changing the session locale
    if (GLib.getenv('STOCKBAR_TEST_RTL') === '1') {
        Main.panel.set_text_direction(Clutter.TextDirection.RTL);
        Main.panel._centerBox.set_text_direction(Clutter.TextDirection.RTL);
    }
    timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
        const file = Gio.File.new_for_path(`${dir}/request`);
        if (busy || !file.query_exists(null))
            return GLib.SOURCE_CONTINUE;
        const [, bytes] = GLib.file_get_contents(file.get_path());
        file.delete(null);
        const request = JSON.parse(new TextDecoder().decode(bytes));
        busy = true;
        handle(dir, request).catch(error => {
            logError(error, 'stockbar probe');
            GLib.file_set_contents(`${dir}/${request.id}.json`, JSON.stringify({error: String(error)}));
        }).finally(() => (busy = false));
        return GLib.SOURCE_CONTINUE;
    });
}

function disableProbe() {
    GLib.source_remove(timer);
    if (settleId)
        GLib.source_remove(settleId);
    dummy?.destroy();
    if (watched)
        watched._fit = originalFit;
}
