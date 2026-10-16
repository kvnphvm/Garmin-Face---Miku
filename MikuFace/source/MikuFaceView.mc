import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Every colour sits on the display's RGB222 lattice (00/55/AA/FF per channel),
// so nothing is approximated at draw time and the simulator matches the watch.
const COLOR_TEAL = 0x55AAAA;
const COLOR_TEXT = 0xFFFFFF;
const COLOR_LABEL = 0xAAAAAA;
const COLOR_SUNRISE = 0xFFAA00;
const COLOR_SUNSET = 0xFF5500;
const COLOR_BATTERY_OK = 0x55FF55;
const COLOR_BATTERY_LOW = 0xFF5555;
const COLOR_TRACK = 0x555555;

// The idle loop is one second long. The watch only grants animation for the
// few seconds it stays in high power mode, so rather than bake a longer clip
// the same second is replayed until the system puts the face back to sleep.
class IdleLoop extends WatchUi.AnimationDelegate {

    private var _view as MikuFaceView;

    function initialize(view as MikuFaceView) {
        AnimationDelegate.initialize();
        _view = view;
    }

    function onAnimationEvent(event as AnimationEvent, options as Dictionary) as Void {
        if (event == WatchUi.ANIMATION_EVENT_COMPLETE) {
            _view.replayIdle();
        } else {
            // Playback can also end because the system stopped it, and a
            // stopped layer keeps showing its last frame. Whatever the reason,
            // hand the area back to the still rather than freeze mid-motion.
            _view.idleStopped();
        }
    }
}

class MikuFaceView extends WatchUi.WatchFace {

    // 260x260 round. Miku on the left and the readouts stacked to her right
    // form one group, and SPRITE_X and COLUMN_CENTER are placed so that group
    // is centred on the screen: her drawn pixels start at x=20 and the widest
    // readout ends at x=240, which straddles CENTER_X evenly.
    //
    // Every row in the column is centred on COLUMN_CENTER, so the shorter ones
    // sit under the middle of the clock. COLUMN_WIDTH is the room the column
    // has before a glyph would reach the bezel.
    private const SPRITE_X = 18;
    private const SPRITE_Y = 66;
    private const COLUMN_CENTER = 191;
    private const COLUMN_WIDTH = 114;
    private const CENTER_X = 130;

    // Miku is the centrepiece, so she is placed first: her drawn pixels run
    // y=68..191, centred on the face. The column follows her, and steps and
    // battery hang below at a 13px pitch. The sun row keeps its place at the
    // top, which leaves a wider gap under it than between the rest — the cost
    // of anchoring her to the middle rather than spacing all four evenly.
    private const SUN_Y = 28;
    private const TIME_Y = 91;
    private const DATE_Y = 127;
    private const TEMP_Y = 153;
    private const CONDITION_Y = 175;
    private const STEPS_Y = 211;
    private const BATTERY_Y = 241;

    // The sunrise and sunset markers are triangles 12px across, each followed
    // by its time, with a wider gap separating the two.
    private const SUN_MARKER_W = 12;
    private const SUN_MARKER_GAP = 4;
    private const SUN_PAIR_GAP = 22;

    // A battery outline with a nub on its right, sized to sit beside XTINY
    // text the way the sunrise and sunset markers sit beside theirs.
    private const BATTERY_W = 22;
    private const BATTERY_H = 12;
    private const BATTERY_NUB_W = 2;
    private const BATTERY_NUB_H = 6;
    private const BATTERY_WALL = 2;
    private const BATTERY_GAP = 6;

    private var _data as WatchData;
    private var _sprite as BitmapResource or Null = null;
    private var _idle as AnimationLayer or Null = null;
    private var _loop as IdleLoop or Null = null;
    private var _animating as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _data = new WatchData();
    }

    function onLayout(dc as Dc) as Void {
        _sprite = WatchUi.loadResource(Rez.Drawables.MikuSprite) as BitmapResource;

        // The layer covers exactly the still sprite's rectangle, so whichever
        // of the two is showing, Miku sits in the same place.
        var idle = new WatchUi.AnimationLayer(Rez.Drawables.MikuIdle, {
            :locX => SPRITE_X,
            :locY => SPRITE_Y,
            :visibility => false
        });
        addLayer(idle);
        _idle = idle;
        _loop = new IdleLoop(self);
    }

    function onShow() as Void {
        startIdle();
    }

    function onHide() as Void {
        stopIdle();
        View.onHide();
    }

    function onExitSleep() as Void {
        startIdle();
    }

    function onEnterSleep() as Void {
        // The system stops playback on its own, but the last frame would stay
        // in the buffer; hiding the layer hands the area back to the still.
        stopIdle();
        WatchUi.requestUpdate();
    }

    private function startIdle() as Void {
        var idle = _idle;
        if (idle == null) {
            return;
        }
        _animating = true;
        idle.setVisible(true);
        idle.play({:delegate => _loop});
    }

    private function stopIdle() as Void {
        var idle = _idle;
        if (idle == null) {
            return;
        }
        _animating = false;
        idle.stop();
        idle.setVisible(false);
    }

    //! Restart the loop, unless the watch has gone back to sleep in the
    //! meantime. Called by IdleLoop when a play-through finishes.
    function replayIdle() as Void {
        var idle = _idle;
        if (idle != null && _animating) {
            idle.play({:delegate => _loop});
        }
    }

    //! Fall back to the still. Called by IdleLoop when playback ends for any
    //! reason other than reaching the end of the clip.
    function idleStopped() as Void {
        var idle = _idle;
        if (idle == null || !_animating) {
            return;
        }
        _animating = false;
        idle.setVisible(false);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        _data.refresh();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawSprite(dc);
        drawSunTimes(dc);
        drawTime(dc);
        drawDate(dc);
        drawWeather(dc);
        drawSteps(dc);
        drawBattery(dc);
    }

    private function drawSprite(dc as Dc) as Void {
        // The animation layer composites over this exact rectangle while it is
        // playing, so drawing the still underneath would only cost time.
        if (_animating) {
            return;
        }
        var sprite = _sprite;
        if (sprite != null) {
            dc.drawBitmap(SPRITE_X, SPRITE_Y, sprite);
        }
    }

    private function drawTime(dc as Dc) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        var text = Lang.format("$1$:$2$", [hour.format("%d"), clock.min.format("%02d")]);

        // 24-hour times are two glyphs wider than "9:05"; drop a size rather
        // than let the digits run under the sprite.
        var font = Graphics.FONT_NUMBER_MEDIUM;
        if (dc.getTextWidthInPixels(text, font) > COLUMN_WIDTH) {
            font = Graphics.FONT_NUMBER_MILD;
        }

        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(COLUMN_CENTER, TIME_Y, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawDate(dc as Dc) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var text = Lang.format("$1$ $2$ $3$", [
            (now.day_of_week as String).toUpper(),
            (now.month as String).toUpper(),
            now.day.format("%d")
        ]);

        dc.setColor(COLOR_TEAL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(COLUMN_CENTER, DATE_Y, Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawWeather(dc as Dc) as Void {
        var temperature = _data.temperature;
        var text = temperature != null
            ? Lang.format("$1$°", [(temperature as Number).format("%d")])
            : "--°";

        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(COLUMN_CENTER, TEMP_Y, Graphics.FONT_TINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var condition = _data.condition;
        dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(COLUMN_CENTER, CONDITION_Y, Graphics.FONT_XTINY,
            condition != null ? condition as String : "NO DATA",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // A marker and a time, twice over, centred as a unit. The two times are
    // rarely the same width — "9:41" against "18:37" — so the row is measured
    // rather than placed at fixed coordinates, which would drift off centre.
    private function drawSunTimes(dc as Dc) as Void {
        var font = Graphics.FONT_XTINY;
        var rise = formatMoment(_data.sunrise);
        var set = formatMoment(_data.sunset);
        var riseWidth = dc.getTextWidthInPixels(rise, font);
        var setWidth = dc.getTextWidthInPixels(set, font);

        var pair = SUN_MARKER_W + SUN_MARKER_GAP;
        var x = CENTER_X - (pair * 2 + riseWidth + setWidth + SUN_PAIR_GAP) / 2;

        drawSunMarker(dc, x + SUN_MARKER_W / 2, SUN_Y, true, COLOR_SUNRISE);
        dc.setColor(COLOR_SUNRISE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pair, SUN_Y, font, rise,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        x += pair + riseWidth + SUN_PAIR_GAP;
        drawSunMarker(dc, x + SUN_MARKER_W / 2, SUN_Y, false, COLOR_SUNSET);
        dc.setColor(COLOR_SUNSET, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pair, SUN_Y, font, set,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawSunMarker(dc as Dc, x as Number, y as Number,
                                   rising as Boolean, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var tip = rising ? y - 5 : y + 5;
        var base = rising ? y + 4 : y - 4;
        dc.fillPolygon([[x - 6, base], [x + 6, base], [x, tip]] as Array<Point2D>);
    }

    private function drawSteps(dc as Dc) as Void {
        var font = Graphics.FONT_XTINY;
        var count = withThousands(_data.steps);
        var goal = _data.stepGoal;

        if (goal <= 0) {
            dc.setColor(COLOR_TEAL, Graphics.COLOR_TRANSPARENT);
            dc.drawText(CENTER_X, STEPS_Y, font, count,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // The count and the goal are drawn as two pieces so the goal can be
        // dimmer, which keeps the number worth reading in front. Centring the
        // pair means measuring both and starting from the left.
        var target = Lang.format(" / $1$", [withThousands(goal)]);
        var countWidth = dc.getTextWidthInPixels(count, font);
        var left = CENTER_X - (countWidth + dc.getTextWidthInPixels(target, font)) / 2;

        dc.setColor(COLOR_TEAL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, STEPS_Y, font, count,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + countWidth, STEPS_Y, font, target,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawBattery(dc as Dc) as Void {
        var percent = _data.battery;
        var font = Graphics.FONT_XTINY;
        var text = Lang.format("$1$%", [percent.format("%d")]);

        var shell = BATTERY_W + BATTERY_NUB_W;
        var left = CENTER_X
            - (shell + BATTERY_GAP + dc.getTextWidthInPixels(text, font)) / 2;
        var top = BATTERY_Y - BATTERY_H / 2;

        dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(left, top, BATTERY_W, BATTERY_H);
        dc.fillRectangle(left + BATTERY_W, BATTERY_Y - BATTERY_NUB_H / 2,
            BATTERY_NUB_W, BATTERY_NUB_H);

        var inner = BATTERY_W - BATTERY_WALL * 2;
        var filled = (inner * percent) / 100;
        if (filled < 1 && percent > 0) {
            // A charge that rounds away to nothing still isn't empty, and an
            // outline with nothing in it reads as a fault rather than as low.
            filled = 1;
        }
        if (filled > 0) {
            dc.setColor(percent <= 20 ? COLOR_BATTERY_LOW : COLOR_BATTERY_OK,
                Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left + BATTERY_WALL, top + BATTERY_WALL,
                filled, BATTERY_H - BATTERY_WALL * 2);
        }

        dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + shell + BATTERY_GAP, BATTERY_Y, font, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The hour is padded so sunrise and sunset are always the same width. An
    // unpadded "4:14" against "18:37" makes the two halves of the row unequal,
    // and then centring the row as a whole leaves the gap between them sitting
    // off to one side, which reads as crooked however the row is placed.
    private function formatMoment(moment as Time.Moment or Null) as String {
        if (moment == null) {
            return "--:--";
        }
        var info = Gregorian.info(moment as Time.Moment, Time.FORMAT_SHORT);
        var hour = info.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour.format("%02d"), info.min.format("%02d")]);
    }

    private function withThousands(value as Number) as String {
        if (value < 1000) {
            return value.format("%d");
        }
        return Lang.format("$1$,$2$", [
            (value / 1000).format("%d"),
            (value % 1000).format("%03d")
        ]);
    }
}
