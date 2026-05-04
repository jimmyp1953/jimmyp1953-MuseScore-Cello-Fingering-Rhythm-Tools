import MuseScore 3.0
import QtQuick 2.0

MuseScore {
    version: "5.1"
    description: "Highlights note attacks on a 16-click-per-measure grid using stable staff/voice traversal."
    menuPath: "Plugins.Notes.Highlight 16 Ticks Per Measure"

    property string attackColor: "#ff0000"
    property string defaultColor: "#000000"
    property bool resetOnly: false

    property int simpleMeterClicksPerMeasure: 16
    property bool useWrittenGridForCompoundMeters: true
    property int gridToleranceTicks: 4

    function isTiedContinuation(note) {
        return note.tieBack !== null && note.tieBack !== undefined;
    }

    function buildMeasureMap(score) {
        var map = {};
        var cursor = score.newCursor();

        cursor.rewind(Cursor.SCORE_START);

        while (cursor.measure) {
            var m = cursor.measure;
            var tick = m.firstSegment.tick;
            var numerator = m.timesigActual.numerator;
            var denominator = m.timesigActual.denominator;
            var measureTicks = numerator * division * 4.0 / denominator;
            var clicksPerMeasure = simpleMeterClicksPerMeasure;

            if (useWrittenGridForCompoundMeters && denominator === 8 && numerator >= 6 && numerator % 3 === 0) {
                clicksPerMeasure = numerator * 2;
            }

            map[tick] = {
                "tick": tick,
                "past": tick + measureTicks,
                "clicks": clicksPerMeasure,
                "gridStep": Math.round(measureTicks / clicksPerMeasure)
            };

            cursor.nextMeasure();
        }

        return map;
    }

    function isOnGrid(localTick, gridStep) {
        var remainder = localTick % gridStep;
        return remainder <= gridToleranceTicks || Math.abs(remainder - gridStep) <= gridToleranceTicks;
    }

    function isGridPosition(cursor, measureMap) {
        if (!cursor.measure || !cursor.segment) return false;

        var m = measureMap[cursor.measure.firstSegment.tick];
        if (!m) return false;

        var t = cursor.segment.tick;
        if (t < m.tick || t >= m.past) return false;

        var localTick = t - m.tick;
        return isOnGrid(localTick, m.gridStep);
    }

    function clearNote(note) {
        note.color = defaultColor;
        if (note.accidental) note.accidental.color = defaultColor;
        if (note.dots) {
            for (var i = 0; i < note.dots.length; i++) {
                if (note.dots[i]) note.dots[i].color = defaultColor;
            }
        }
    }

    function colorNote(note) {
        note.color = attackColor;
        if (note.accidental) note.accidental.color = attackColor;
        if (note.dots) {
            for (var i = 0; i < note.dots.length; i++) {
                if (note.dots[i]) note.dots[i].color = attackColor;
            }
        }
    }

    function clearChord(chord) {
        for (var i = 0; i < chord.notes.length; i++) clearNote(chord.notes[i]);
    }

    function colorChordAttacks(chord) {
        for (var i = 0; i < chord.notes.length; i++) {
            if (!isTiedContinuation(chord.notes[i])) colorNote(chord.notes[i]);
        }
    }

    function getSelectionRange() {
        var cursor = curScore.newCursor();
        var range = {
            "fullScore": false,
            "startStaff": 0,
            "endStaff": curScore.nstaves - 1,
            "endTick": curScore.lastSegment.tick + 1,
            "rewindMode": Cursor.SCORE_START
        };

        cursor.rewind(Cursor.SELECTION_START);

        if (!cursor.segment) {
            range.fullScore = true;
            range.rewindMode = Cursor.SCORE_START;
            return range;
        }

        range.startStaff = cursor.staffIdx;
        cursor.rewind(Cursor.SELECTION_END);
        range.endStaff = cursor.staffIdx;
        range.endTick = cursor.tick === 0 ? curScore.lastSegment.tick + 1 : cursor.tick;
        range.rewindMode = Cursor.SELECTION_START;

        return range;
    }

    function applyToSelectionOrScore(callback, measureMap) {
        var range = getSelectionRange();
        var cursor = curScore.newCursor();

        for (var staff = range.startStaff; staff <= range.endStaff; staff++) {
            for (var voice = 0; voice < 4; voice++) {
                cursor.staffIdx = staff;
                cursor.voice = voice;
                cursor.rewind(range.rewindMode);

                cursor.staffIdx = staff;
                cursor.voice = voice;

                while (cursor.segment && (range.fullScore || cursor.tick < range.endTick)) {
                    if (cursor.element && cursor.element.type == Element.CHORD) {
                        callback(cursor, measureMap);
                    }

                    cursor.next();
                }
            }
        }
    }

    function clearExistingHighlight(cursor, measureMap) {
        clearChord(cursor.element);
    }

    function applySixteenthGridHighlight(cursor, measureMap) {
        if (isGridPosition(cursor, measureMap)) {
            colorChordAttacks(cursor.element);
        }
    }

    onRun: {
        if (!curScore) {
            Qt.quit();
            return;
        }

        var measureMap = buildMeasureMap(curScore);

        curScore.startCmd();

        applyToSelectionOrScore(clearExistingHighlight, measureMap);

        if (!resetOnly) {
            applyToSelectionOrScore(applySixteenthGridHighlight, measureMap);
        }

        curScore.endCmd();
        Qt.quit();
    }
}
