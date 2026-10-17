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
        this._indicator = new StockbarIndicator();
        Main.panel.addToStatusArea(ExtensionUtils.getCurrentExtension().uuid, this._indicator, 0, 'right');
    }

    disable() {
        this._indicator.destroy();
        this._indicator = null;
    }
}

function init() {
    return new Extension();
}
