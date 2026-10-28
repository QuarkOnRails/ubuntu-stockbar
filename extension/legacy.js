/* exported init */
'use strict';

const {Clutter, Gio, GLib, GObject, St} = imports.gi;
const Main = imports.ui.main;
const PanelMenu = imports.ui.panelMenu;
const PopupMenu = imports.ui.popupMenu;
const ExtensionUtils = imports.misc.extensionUtils;

//@@CORE@@

class Extension {
    enable() {
        this._stockbar = new Stockbar(ExtensionUtils.getCurrentExtension().uuid);
    }

    disable() {
        this._stockbar.destroy();
        this._stockbar = null;
    }
}

function init() {
    return new Extension();
}
