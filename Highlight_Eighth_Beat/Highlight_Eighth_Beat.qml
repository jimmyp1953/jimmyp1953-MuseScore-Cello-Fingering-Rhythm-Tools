import MuseScore 3.0
import QtQuick 2.0


MuseScore {
    version: "5.0"
    description: "Highlights note attacks on the correct beat grid for simple and compound meters."
    menuPath: "Plugins.Notes.Highlight Beat Attacks Adaptive"

    property string attackColor: "#ff0000"
    property string defaultColor: "#000000"
    property bool resetOnly: false

    function isTiedContinuation(note) {
        return note.tieBack !== null && note.tieBack !== undefined;
    }

    function beatUnitTicksForMeasure(measure) {
        var numerator = measure.timesigActual.numerator;
        var denominator = measure.timesigActual.denominator;

        // Compound meters: 6/8, 9/8, 12/8, etc.
        // Main beat is dotted quarter = 3 eighths = 1.5 quarters.
        if (denominator === 8 && numerator >= 6 && numerator % 3 === 0) {
            return division * 3 / 2;
        }

        // Simple meters: 2/4, 3/4, 4/4, etc.
        // Main beat is denominator note.
        return division * 4 / denominator;
    }

    function isBeatPosition(cursor) {
        if (!cursor.measure) return false;

        var beatTicks = beatUnitTicksForMeasure(cursor.measure);
        var measureStartTick = cursor.measure.firstSegment.tick;
        var localTick = cursor.tick - measureStartTick;

        return localTick >= 0 && (localTick % beatTicks) === 0;
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
        for (var i = 0; i < chord.notes.length; i++) {
            clearNote(chord.notes[i]);
        }
    }

    function colorChordAttacks(chord) {
        for (var i = 0; i < chord.notes.length; i++) {
            var note = chord.notes[i];

            if (!isTiedContinuation(note)) {
                colorNote(note);
            }
        }
    }

    function getEndTick() {
        var c = curScore.newCursor();

        c.rewind(Cursor.SELECTION_START);

        if (!c.segment) {
            return curScore.lastSegment.tick + 1;
        }

        c.rewind(Cursor.SELECTION_END);

        if (c.tick === 0) {
            return curScore.lastSegment.tick + 1;
        }

        return c.tick;
    }

    function rewindToStart(cursor) {
        cursor.rewind(Cursor.SELECTION_START);

        if (!cursor.segment) {
            cursor.rewind(Cursor.SCORE_START);
        }
    }

    onRun: {
        if (!curScore) {
            Qt.quit();
            return;
        }

        var endTick = getEndTick();

        curScore.startCmd();

        for (var track = 0; track < curScore.ntracks; track++) {
            var clearCursor = curScore.newCursor();
            clearCursor.track = track;
            rewindToStart(clearCursor);

            while (clearCursor.segment && clearCursor.tick < endTick) {
                if (clearCursor.element && clearCursor.element.type === Element.CHORD) {
                    clearChord(clearCursor.element);
                }

                clearCursor.next();
            }
        }

        if (!resetOnly) {
            for (var track2 = 0; track2 < curScore.ntracks; track2++) {
                var cursor = curScore.newCursor();
                cursor.track = track2;
                rewindToStart(cursor);

                while (cursor.segment && cursor.tick < endTick) {
                    if (cursor.element && cursor.element.type === Element.CHORD && isBeatPosition(cursor)) {
                        colorChordAttacks(cursor.element);
                    }

                    cursor.next();
                }
            }
        }

        curScore.endCmd();
        Qt.quit();
    }
}