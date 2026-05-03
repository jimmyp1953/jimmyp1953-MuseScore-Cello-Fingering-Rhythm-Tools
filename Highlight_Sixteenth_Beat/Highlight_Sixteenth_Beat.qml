import MuseScore 3.0
import QtQuick 2.0

MuseScore {
    description: "Highlights real note attacks that land on sixteenth-note subdivision positions.";
    requiresScore: true;
    version: "1.0";
    menuPath: "Plugins.Notes.Highlight Sixteenth Subdivision Attacks";

    property string attackColor: "#ff0000"

    function buildMeasureMap(score) {
        var map = {};
        var cursor = score.newCursor();

        cursor.rewind(Cursor.SCORE_START);

        while (cursor.measure) {
            var m = cursor.measure;
            var tick = m.firstSegment.tick;

            map[tick] = {
                "tick": tick,
                "past": tick + m.timesigActual.numerator * division * 4.0 / m.timesigActual.denominator
            };

            cursor.nextMeasure();
        }

        return map;
    }

    function isTiedContinuation(note) {
        return note.tieBack !== null && note.tieBack !== undefined;
    }

    function isRealAttack(note) {
        return !isTiedContinuation(note);
    }

    function isSixteenthSubdivision(cursor, measureMap) {
        var t = cursor.segment.tick;
        var m = measureMap[cursor.measure.firstSegment.tick];

        if (!m || t < m.tick || t >= m.past) return false;

        var sixteenthTicks = division / 4;
        var localTick = t - m.tick;

        return (localTick % sixteenthTicks) == 0;
    }

    function colorNote(note) {
        note.color = attackColor;
        if (note.accidental) note.accidental.color = attackColor;
        if (note.dots) for (var i = 0; i < note.dots.length; i++) if (note.dots[i]) note.dots[i].color = attackColor;
    }

    function colorChordAttacksOnly(chord) {
        for (var i = 0; i < chord.notes.length; i++) {
            if (isRealAttack(chord.notes[i])) colorNote(chord.notes[i]);
        }
    }

    function applyToSelectionOrScore(cb, measureMap) {
        var staveBeg;
        var staveEnd;
        var tickEnd;
        var rewindMode;
        var toEOF;

        var cursor = curScore.newCursor();
        cursor.rewind(Cursor.SELECTION_START);

        if (cursor.segment) {
            staveBeg = cursor.staffIdx;
            cursor.rewind(Cursor.SELECTION_END);
            staveEnd = cursor.staffIdx;

            if (!cursor.tick) {
                toEOF = true;
            } else {
                toEOF = false;
                tickEnd = cursor.tick;
            }

            rewindMode = Cursor.SELECTION_START;
        } else {
            staveBeg = 0;
            staveEnd = curScore.nstaves - 1;
            toEOF = true;
            rewindMode = Cursor.SCORE_START;
        }

        for (var stave = staveBeg; stave <= staveEnd; stave++) {
            for (var voice = 0; voice < 4; voice++) {
                cursor.staffIdx = stave;
                cursor.voice = voice;
                cursor.rewind(rewindMode);

                cursor.staffIdx = stave;
                cursor.voice = voice;

                while (cursor.segment && (toEOF || cursor.tick < tickEnd)) {
                    if (cursor.element && cursor.element.type == Element.CHORD) {
                        cb(cursor, measureMap);
                    }

                    cursor.next();
                }
            }
        }
    }

    function highlightSubdivisionAttack(cursor, measureMap) {
        if (isSixteenthSubdivision(cursor, measureMap)) {
            colorChordAttacksOnly(cursor.element);
        }
    }

    onRun: {
        if (!curScore) {
            Qt.quit();
            return;
        }

        var measureMap = buildMeasureMap(curScore);

        curScore.startCmd();
        applyToSelectionOrScore(highlightSubdivisionAttack, measureMap);
        curScore.endCmd();

        Qt.quit();
    }
}