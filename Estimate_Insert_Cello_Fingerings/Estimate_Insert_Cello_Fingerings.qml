//=============================================================================
//  Cello Fingering - shift-aware high-position correction
//=============================================================================
import QtQuick 2.2
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.Fingering.Cello Fingering (Shift Aware)"
    version: "2.1"
    description: "Estimates cello fingerings and avoids 4th finger above G# using candidate scoring."
    requiresScore: true

    property int fingeringFontSize: 10
    property real textOffsetX: 0.65
    property real textOffsetY: -0.3
    property bool skipRepeatedFingerings: true
    property bool skipTiedContinuations: true
    property int avoidFourthAbovePitch: 68
    property int lookaheadChords: 6

    property variant noteNames: [ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" ]
    property variant celloOpenStrings: [57, 50, 43, 36]

    // Original fingering chart (unchanged)
    property var fingeringChart: ({
        "A:0": "0", "A:1": "1", "A:2": "1", "A:3": "2", "A:4": "3", "A:5": "4", "A:6": "4",
        "A:7": "1", "A:8": "2", "A:9": "3", "A:10": "4", "A:11": "1", "A:12": "2", "A:13": "3", "A:14": "4",
        "D:0": "0", "D:1": "1", "D:2": "1", "D:3": "2", "D:4": "3", "D:5": "4", "D:6": "4",
        "D:7": "1", "D:8": "2", "D:9": "3", "D:10": "4", "D:11": "1", "D:12": "2", "D:13": "3", "D:14": "4",
        "G:0": "0", "G:1": "1", "G:2": "1", "G:3": "2", "G:4": "3", "G:5": "4", "G:6": "4",
        "G:7": "1", "G:8": "2", "G:9": "3", "G:10": "4", "G:11": "1", "G:12": "2", "G:13": "3", "G:14": "4",
        "C:0": "0", "C:1": "1", "C:2": "1", "C:3": "2", "C:4": "3", "C:5": "4", "C:6": "4",
        "C:7": "1", "C:8": "2", "C:9": "3", "C:10": "4", "C:11": "1", "C:12": "2", "C:13": "3", "C:14": "4"
    })

    function noteName(pitch) { return noteNames[(pitch - 12) % 12]; }
    function isTiedContinuation(note) { return note.tieBack !== null && note.tieBack !== undefined; }

    function norm7(offset) {
        var r = offset % 7;
        if (r < 0) r += 7;
        return r;
    }

    function chartFinger(stringName, offset) {
        var direct = fingeringChart[stringName + ":" + offset];
        if (direct !== undefined) return direct;

        // If the chart does not extend far enough, estimate a higher-position frame.
        var r = norm7(offset);

        if (offset >= 8) {
            if (r === 0 || r === 1 || r === 2) return "1";
            if (r === 3 || r === 4) return "2";
            if (r === 5 || r === 6) return "3";
        }

        if (r === 0) return "0";
        if (r === 1 || r === 2) return "1";
        if (r === 3) return "2";
        if (r === 4) return "3";
        if (r === 5 || r === 6) return "4";

        return "1";
    }

    function upcomingGoesHigher(cursor, currentPitch) {
        if (!cursor) return false;

        var c = curScore.newCursor();
        c.staffIdx = cursor.staffIdx;
        c.voice = cursor.voice;
        c.rewind(0);
        c.staffIdx = cursor.staffIdx;
        c.voice = cursor.voice;

        while (c.segment && c.segment.tick <= cursor.segment.tick) c.next();

        var checked = 0;

        while (c.segment && checked < lookaheadChords) {
            if (c.element && c.element.type == Element.CHORD) {
                checked++;
                var notes = c.element.notes;
                for (var i = 0; i < notes.length; i++) {
                    if (skipTiedContinuations && isTiedContinuation(notes[i])) continue;
                    if (notes[i].pitch > currentPitch) return true;
                }
            }

            c.next();
        }

        return false;
    }

    function candidateScore(pitch, stringName, offset, finger, lastFinger, higherComing) {
        var score = offset;

        if (finger === lastFinger) score -= 1;

        // The real fix: do not force a high note into finger 3 after choosing a bad candidate.
        // Instead, make any candidate using 4 above G# very unattractive, so the engine shifts
        // into a setup that can use 1/2/3.
        if (pitch >= avoidFourthAbovePitch && finger === "4") score += 100;

        // Above G#, prefer a shift/re-anchor. If the line continues upward, 1 is best;
        // otherwise 3 is usually more comfortable than 4.
        if (pitch >= avoidFourthAbovePitch) {
            if (higherComing && finger === "1") score -= 8;
            if (higherComing && finger === "2") score -= 4;
            if (!higherComing && finger === "3") score -= 4;
            if (!higherComing && finger === "1") score -= 2;
        }

        // Avoid extreme reaching on lower strings if the note can be played closer elsewhere.
        if (offset > 16) score += 10;

        return score;
    }

    function estimateFingering(note, lastFinger, cursor) {
        var pitch = note.pitch;
        var bestFinger = "";
        var bestScore = 9999;
        var higherComing = upcomingGoesHigher(cursor, pitch);

        for (var i = 0; i < celloOpenStrings.length; i++) {
            var openPitch = celloOpenStrings[i];

            if (pitch >= openPitch) {
                var offset = pitch - openPitch;
                var stringName = noteName(openPitch);
                var finger = chartFinger(stringName, offset);
                var score = candidateScore(pitch, stringName, offset, finger, lastFinger, higherComing);

                if (score < bestScore) {
                    bestScore = score;
                    bestFinger = finger;
                }
            }
        }

        if (bestFinger === "") bestFinger = "1";

        // Final safety: no 4 above G# unless there was literally no better candidate.
        if (pitch >= avoidFourthAbovePitch && bestFinger === "4") bestFinger = higherComing ? "1" : "3";

        return bestFinger;
    }

    function addFingerText(notes, textElement, lastFinger, cursor) {
        var labelLines = [];
        var newLastFinger = lastFinger;

        for (var i = 0; i < notes.length; i++) {
            var note = notes[i];
            if (skipTiedContinuations && isTiedContinuation(note)) continue;

            var finger = estimateFingering(note, lastFinger, cursor);

            if (skipRepeatedFingerings && finger === lastFinger) {
                newLastFinger = finger;
                lastFinger = finger;
                continue;
            }

            labelLines.push(finger);
            newLastFinger = finger;
            lastFinger = finger;
        }

        textElement.text = labelLines.join("\n");
        return newLastFinger;
    }

    function makeFingerTextElement() {
        var textElement = newElement(Element.STAFF_TEXT);
        textElement.autoplace = true;
        textElement.fontSize = fingeringFontSize;
        textElement.offsetX = textOffsetX;
        textElement.offsetY = textOffsetY;
        textElement.align = 2;
        return textElement;
    }

    onRun: {
        if (!curScore) { Qt.quit(); return; }

        var lastFinger = "";
        var startStaff = 0;
        var endStaff = curScore.nstaves - 1;
        var cursor = curScore.newCursor();

        curScore.startCmd();

        for (var staff = startStaff; staff <= endStaff; staff++) {
            lastFinger = "";
            for (var voice = 0; voice < 4; voice++) {
                cursor.rewind(0);
                cursor.staffIdx = staff;
                cursor.voice = voice;

                while (cursor.segment) {
                    if (cursor.element && cursor.element.type == Element.CHORD) {
                        var chord = cursor.element;

                        // Grace notes
                        var graceChords = chord.graceNotes;
                        for (var i = 0; i < graceChords.length; i++) {
                            var graceText = makeFingerTextElement();
                            graceText.offsetX = -2.5 * (graceChords.length - i);
                            lastFinger = addFingerText(graceChords[i].notes, graceText, lastFinger, cursor);
                            if (graceText.text.length > 0) cursor.add(graceText);
                        }

                        // Main chord
                        var textElement = makeFingerTextElement();
                        lastFinger = addFingerText(chord.notes, textElement, lastFinger, cursor);
                        if (textElement.text.length > 0) cursor.add(textElement);
                    }
                    cursor.next();
                }
            }
        }

        curScore.endCmd();
        Qt.quit();
    }
}