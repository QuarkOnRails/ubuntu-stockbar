// run with node test/layout_test.js, no npm dependencies
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const {fitStocks, sideRoom, scrollLayout, scrollAdvance} = vm.runInNewContext(
    fs.readFileSync(path.join(__dirname, '../extension/layout.js'), 'utf8') +
    '\n({fitStocks, sideRoom, scrollLayout, scrollAdvance});');

let cases = 0;
function check(widths, room, spacing, expected) {
    const actual = JSON.parse(JSON.stringify(fitStocks(widths, room, spacing, 10)));
    assert.deepEqual(actual, expected, JSON.stringify({widths, room, spacing}));
    cases++;
}

check([], 100, 10, {onRight: 0, shown: 0, more: false, widths: []});
check([40], 100, 10, {onRight: 1, shown: 1, more: false, widths: [40]});
check([45, 45, 45, 45], 100, 10, {onRight: 2, shown: 4, more: false, widths: [45, 45, 45, 45]});
// the marker pushes a stock left and the fourth no longer fits
check([45, 45, 45, 45, 45], 100, 10, {onRight: 1, shown: 3, more: true, widths: [45, 45, 45]});
// stocks after the split stay left, even if they fit a gap on the right
check([70, 60, 20], 100, 10, {onRight: 1, shown: 3, more: false, widths: [70, 60, 20]});
check([40, 40, 40, 40, 40], 100, 0, {onRight: 2, shown: 4, more: true, widths: [40, 40, 40, 40]});
check([200], 100, 10, {onRight: 1, shown: 1, more: false, widths: [100]});
check([200, 60], 100, 10, {onRight: 1, shown: 2, more: false, widths: [100, 60]});
check([200, 60, 60], 100, 10, {onRight: 1, shown: 2, more: true, widths: [80, 60]});
check([200, 200, 200], 100, 10, {onRight: 1, shown: 2, more: true, widths: [80, 100]});
// don't shorten a stock that fits a whole side just to fit the marker
check([95, 95, 95], 100, 10, {onRight: 0, shown: 1, more: true, widths: [95]});
check([20], 10, 10, {onRight: 1, shown: 1, more: false, widths: [10]});
check([20, 20], 10, 10, {onRight: 1, shown: 2, more: false, widths: [10, 10]});
check([20], 9, 10, {onRight: 0, shown: 0, more: false, widths: []});
check([20], 0, 10, {onRight: 0, shown: 0, more: false, widths: []});
check([20], -10, 10, {onRight: 0, shown: 0, more: false, widths: []});
check([3], 5, 10, {onRight: 1, shown: 1, more: false, widths: [3]});
check([45.1, 45.1, 45.1], 100.9, 10, {onRight: 1, shown: 2, more: true, widths: [46, 46]});
check(Array(10000).fill(150), 400, 14, {onRight: 2, shown: 4, more: true, widths: [150, 150, 150, 150]});

// check both width limits and the truncation policy across varied inputs
for (const room of [0, 9, 10, 25, 99, 100, 100.5]) {
    for (const widths of [[5, 100, 20], [200, 10, 500], [45, 45, 45, 45, 45], [100, 1, 100], []]) {
        const result = fitStocks(widths, room, 10, 10);
        const used = list => list.reduce((a, b) => a + b, 0) + Math.max(0, list.length - 1) * 10;
        const right = result.widths.slice(0, result.onRight);
        if (result.more)
            right.push(10);
        assert(used(right) <= Math.floor(room));
        assert(used(result.widths.slice(result.onRight)) <= Math.floor(room));
        assert.equal(result.widths.length, result.shown);
        assert(result.onRight <= result.shown && result.shown <= widths.length);
        result.widths.forEach((width, i) => {
            assert(width > 0 && width <= Math.ceil(widths[i]));
            if (widths[i] <= Math.floor(room))
                assert.equal(width, Math.ceil(widths[i]));
        });
        if (result.shown < widths.length && room >= 10)
            assert.equal(result.more, true);
        cases++;
    }
}

assert.equal(sideRoom(1920, 960, 200, 300, 200, 24), 535);
assert.equal(sideRoom(1920, 990, 200, 300, 200, 24), 505);
assert.equal(sideRoom(1366, 683, 200, 300, 200, 24), 258);
assert.equal(sideRoom(100, 50, 40, 40, 50, 24), 0);
assert.equal(sideRoom(1920, 960, 200, 300, 201, 24), 534);
console.log(`Layout: ${cases} fit cases and 5 geometry cases passed`);

const loop = scrollLayout([40.2, 90, 400], 100, 14);
assert.deepEqual(Array.from(loop.starts), [0, 55, 159]);
assert.equal(loop.length, 573);
assert.equal(loop.width, 100);
assert.equal(scrollLayout([40], 100, 14).width, 27);
assert.equal(scrollLayout([], 100, 14).width, 0);
assert.equal(scrollLayout([40], -10, 14).width, 0);
assert.equal(scrollAdvance(0, 0, 1000, 100), 0);
assert.equal(scrollAdvance(0, 1, 1000, 100), 8);
assert.equal(scrollAdvance(0, 5, 1000, 100), 40);
assert.equal(scrollAdvance(0, 10, 1000, 100), 80);
assert.equal(scrollAdvance(90, 10, 1000, 100), 70);
assert.equal(scrollAdvance(0, 10, 5000, 100), 0);
let position = 0;
for (let frame = 0; frame < 100; frame++)
    position = scrollAdvance(position, 5, 10, 100);
assert(Math.abs(position - scrollAdvance(0, 5, 1000, 100)) < 0.00001);
console.log('Scroll: sizing, speed, wraparound and frame-rate independence passed');
