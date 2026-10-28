// inlined before core.js in both shell variants

function sideRoom(width, midpoint, leftWidth, rightWidth, others, padding) {
    // leave one pixel for the panel's allocation rounding
    return Math.max(0, Math.floor(Math.min(midpoint - leftWidth, width - rightWidth - midpoint) -
        others / 2 - padding - 1));
}

function scrollLayout(widths, room, spacing) {
    const starts = [];
    let length = 0;
    for (const width of widths) {
        starts.push(length);
        length += Math.ceil(width) + spacing;
    }
    return {starts, length, width: Math.max(0, Math.min(Math.floor(room), Math.floor(length / 2)))};
}

function scrollAdvance(position, speed, milliseconds, length) {
    return (position + speed * 8 * milliseconds / 1000) % length;
}

function fitStocks(widths, room, spacing, moreWidth) {
    room = Math.max(0, Math.floor(room));
    widths = widths.map(width => Math.ceil(width));
    moreWidth = Math.ceil(moreWidth);
    const empty = {onRight: 0, shown: 0, more: false, widths: []};
    if (room === 0 || widths.length === 0)
        return empty;

    for (let shown = widths.length; shown >= 0; shown--) {
        const more = shown < widths.length;
        if (more && moreWidth > room)
            continue;

        const fitted = [];
        let rightUsed = more ? moreWidth : 0;
        let onRight = 0;
        for (; onRight < shown; onRight++) {
            const gap = onRight > 0 || more ? spacing : 0;
            // only shorten oversized stocks, leaving room for the overflow marker
            const width = widths[onRight] > room
                ? room - rightUsed - gap : widths[onRight];
            if ((width < moreWidth && widths[onRight] > room) || rightUsed + gap + width > room)
                break;
            fitted.push(width);
            rightUsed += gap + width;
        }

        let leftUsed = 0;
        for (let i = onRight; i < shown; i++) {
            const width = Math.min(widths[i], room);
            leftUsed += (i > onRight ? spacing : 0) + width;
            if (leftUsed > room)
                break;
            fitted.push(width);
        }
        if (leftUsed <= room && !fitted.some((width, i) => width <= 0 || (widths[i] > room && width < moreWidth)))
            return {onRight, shown, more, widths: fitted};
    }
    return empty;
}
