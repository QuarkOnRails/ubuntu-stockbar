// two clipped views of the same loop, with the clock between them
class StockbarScroll {
    constructor(halves, items, speed, anchor) {
        this._halves = halves;
        this._items = items;
        this._speed = speed;
        this._anchor = anchor;
        this.position = 0;
        this._timeline = new Clutter.Timeline({actor: halves[0], duration: 1000, repeat_count: -1});
        this._frameId = this._timeline.connect('new-frame', timeline => {
            this.position = scrollAdvance(this.position, this._speed, timeline.get_delta(), this.layout.length);
            this._position();
        });
        this._views = halves.map(half => {
            const viewport = new St.Widget({
                layout_manager: new Clutter.FixedLayout(),
                clip_to_allocation: true,
                y_align: Clutter.ActorAlign.CENTER,
                width: 0,
            });
            half._box.add_child(viewport);
            const strips = [0, 1].map(() => {
                const strip = new St.BoxLayout({style_class: 'stockbar-box'});
                for (const item of items)
                    strip.add_child(createLabel(item.bar_text, `stockbar-label ${directionClass(item)}`, item.stale));
                viewport.add_child(strip);
                return strip;
            });
            const mappedId = viewport.connect('notify::mapped', () => this._syncAnimation());
            return {viewport, strips, mappedId};
        });
        this._menuIds = halves.map(half => half.menu.connect('open-state-changed', () => this._syncAnimation()));
    }

    anchor() {
        if (!this.layout)
            return this._anchor;
        const {starts} = this.layout;
        let index = starts.length - 1;
        while (index > 0 && starts[index] > this.position)
            index--;
        return {symbol: this._items[index].symbol, offset: this.position - starts[index]};
    }

    fit(room) {
        const labels = this._views[0].strips[0].get_children();
        const widths = labels.map(label => {
            label.ensure_style();
            return Math.ceil(label.clutter_text.get_preferred_width(-1)[1]);
        });
        const strip = this._views[0].strips[0];
        const spacing = strip.get_theme_node().get_length('spacing');
        const height = Math.ceil(Math.max(...labels.map(label => label.get_preferred_height(-1)[1])));
        const layout = scrollLayout(widths, room, spacing);
        const key = JSON.stringify({layout, widths, height});
        if (key === this._lastLayout)
            return;
        this._lastLayout = key;

        const anchor = this.anchor();
        this.layout = layout;
        const index = anchor ? this._items.findIndex(item => item.symbol === anchor.symbol) : -1;
        this.position = index < 0 ? 0 : layout.starts[index] + Math.min(anchor.offset, widths[index] + spacing - 1);
        for (const {viewport, strips} of this._views) {
            viewport.set_size(layout.width, height);
            for (const track of strips) {
                track.get_children().forEach((label, i) => (label.width = widths[i]));
                track.set_size(layout.length - spacing, height);
            }
        }
        for (const half of this._halves) {
            half.visible = layout.width > 0;
            half.container.queue_relayout();
        }
        this._position();
        this._syncAnimation();
    }

    _position() {
        const {width, length} = this.layout;
        this._views.forEach(({strips}, side) => {
            const offset = (this.position + side * width) % length;
            strips[0].translation_x = -offset;
            strips[1].translation_x = length - offset;
        });
    }

    _syncAnimation() {
        const running = this.layout?.width > 0 && this._views.every(view => view.viewport.mapped) &&
            !this._halves.some(half => half.menu.isOpen);
        if (running && !this._timeline.is_playing())
            this._timeline.start();
        else if (!running && this._timeline.is_playing())
            this._timeline.pause();
    }

    destroy() {
        this._timeline.stop();
        this._timeline.disconnect(this._frameId);
        this._halves.forEach((half, i) => half.menu.disconnect(this._menuIds[i]));
        for (const {viewport, mappedId} of this._views) {
            viewport.disconnect(mappedId);
            viewport.destroy();
        }
    }
}
