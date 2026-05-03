//=============================================================================
//  Cello Fingering Engine v3
//=============================================================================
import QtQuick 2.2
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.Fingering.Estimate Cello Fingerings V3 Frame Based"
    version: "3.4"
    description: "Estimates cello fingerings with conservative frame logic, chromatic-neighbor handling, and avoids 4 above high A."
    requiresScore: true

    property variant showNoteNames: false
    property variant hideStringNames: true
    property variant showPitch: false
    property variant debug: false

    property int fingeringFontSize: 10
    property bool stackStringAndFinger: false
    property bool showStringOnlyOnChange: true
    property bool skipRepeatedFingerings: true
    property bool skipTiedContinuations: true
    property bool enableLookaheadFrameCorrection: true
    property int lookaheadChords: 6

    // Avoid 4 in high position before thumb-position technique is introduced.
    // MIDI 69 = A4. Above this, a generated 4 is converted to 1 or 3.
    property bool avoidFourthAboveHighA: true
    property int avoidFourthAbovePitch: 69

    property real textOffsetX: 0.65
    property real textOffsetY: -0.3

    property variant noteNames: [ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" ]
    property variant celloDev: [57, 50, 43, 36] // A3, D3, G2, C2

    function octave(pitch) { return Math.floor((pitch - 12) / 12); }
    function noteName(pitch) { return noteNames[(pitch - 12) % 12]; }
    function fullNoteName(pitch) { return noteName(pitch) + octave(pitch); }
    function instrument() { return celloDev; }

    function isTiedContinuation(note) { return note.tieBack !== null && note.tieBack !== undefined; }

    function norm7(offset) {
        var r = offset % 7;
        if (r < 0) r += 7;
        return r;
    }

    function openPitchForStringName(openStrings, stringName) {
        for (var i = 0; i < openStrings.length; i++) if (noteName(openStrings[i]) === stringName) return openStrings[i];
        return -1;
    }

    function positionFromOffset(offset) {
        if (offset <= 7) return 1;
        if (offset <= 9) return 2;
        if (offset <= 11) return 3;
        if (offset <= 13) return 4;
        if (offset <= 15) return 5;
        if (offset <= 17) return 6;
        return 7;
    }

    function baseFingerForFrameOffset(frameOffset) {
        if (frameOffset === 0) return "0";
        if (frameOffset === 1 || frameOffset === 2) return "1";
        if (frameOffset === 3) return "2";
        if (frameOffset === 4) return "3";
        if (frameOffset === 5 || frameOffset === 6) return "4";
        return "1";
    }

    function baseFingerForHigherPositionFrame(frameOffset) {
        if (frameOffset === 0) return "1";
        if (frameOffset === 1 || frameOffset === 2) return "1";
        if (frameOffset === 3 || frameOffset === 4) return "2";
        if (frameOffset === 5) return "3";
        if (frameOffset === 6) return "4";
        return "1";
    }

    function noShiftFinger(stringName, offset) {
        var r = norm7(offset);

        // Default first-position/no-shift assumption:
        // 0=open; 1/2=1; 3=2; 4=3; 5/6=4.
        if (offset <= 7) return baseFingerForFrameOffset(r);

        var pos = positionFromOffset(offset);
        var positionBaseOffset = 7 + ((pos - 1) * 2);
        var frameOffset = offset - positionBaseOffset;
        while (frameOffset < 0) frameOffset += 7;
        frameOffset = norm7(frameOffset);

        return baseFingerForHigherPositionFrame(frameOffset);
    }

    function noteMatchesStringOffset(note, stringName, targetReducedOffset) {
        var openPitch = openPitchForStringName(instrument(), stringName);
        if (openPitch < 0 || note.pitch < openPitch) return false;
        return norm7(note.pitch - openPitch) === targetReducedOffset;
    }

    function upcomingHasStringOffset(cursor, stringName, targetReducedOffset) {
        if (!enableLookaheadFrameCorrection || !cursor) return false;

        var c = curScore.newCursor();
        c.staffIdx = cursor.staffIdx;
        c.voice = cursor.voice;
        c.rewind(0);
        c.staffIdx = cursor.staffIdx;
        c.voice = cursor.voice;

        while (c.segment && c.segment.tick <= cursor.segment.tick) c.next();

        var checkedChords = 0;
        while (c.segment && checkedChords < lookaheadChords) {
            if (c.element && c.element.type == Element.CHORD) {
                checkedChords++;
                var notes = c.element.notes;
                for (var i = 0; i < notes.length; i++) {
                    if (skipTiedContinuations && isTiedContinuation(notes[i])) continue;
                    if (noteMatchesStringOffset(notes[i], stringName, targetReducedOffset)) return true;
                }
            }
            c.next();
        }
        return false;
    }

    function previousHasStringOffset(cursor, stringName, targetReducedOffset) {
        if (!enableLookaheadFrameCorrection || !cursor) return false;

        var c = curScore.newCursor();
        c.staffIdx = cursor.staffIdx;
        c.voice = cursor.voice;
        c.rewind(0);
        c.staffIdx = cursor.staffIdx;
        c.voice = cursor.voice;

        var recentMatches = [];
        var checkedChords = 0;

        while (c.segment && c.segment.tick < cursor.segment.tick) {
            if (c.element && c.element.type == Element.CHORD) {
                checkedChords++;

                var notes = c.element.notes;
                for (var i = 0; i < notes.length; i++) {
                    if (skipTiedContinuations && isTiedContinuation(notes[i])) continue;
                    if (noteMatchesStringOffset(notes[i], stringName, targetReducedOffset)) recentMatches.push(true);
                }

                if (checkedChords > lookaheadChords) {
                    checkedChords = lookaheadChords;
                    if (recentMatches.length > lookaheadChords) recentMatches.shift();
                }
            }

            c.next();
        }

        return recentMatches.length > 0;
    }

    function hasChromaticNeighborFrame(cursor, stringName, lowerReducedOffset, upperReducedOffset) {
        return upcomingHasStringOffset(cursor, stringName, upperReducedOffset) || previousHasStringOffset(cursor, stringName, lowerReducedOffset);
    }

    function frameCorrectedFinger(stringName, offset, defaultFinger, cursor) {
        var r = norm7(offset);

        // Chromatic-neighbor correction:
        // If two adjacent semitones occur in the same local passage, prefer adjacent fingers
        // rather than treating the flat/sharp as a wide diatonic reach.
        // Example: G-Ab should be 1-2, not 2-4.
        if (r === 5 && upcomingHasStringOffset(cursor, stringName, 6)) return "1";
        if (r === 6 && previousHasStringOffset(cursor, stringName, 5)) return "2";

        // Conservative rule:
        // Do NOT remap B-flat/B-natural/C on G string or E/F on C string merely because
        // a later note suggests a possible shift. Keep stable no-shift defaults unless
        // there is a direct chromatic-neighbor reason above.

        // G string no-shift stability:
        // G=0, Ab/G#=1, A=2, Bb=3, B=4, C=5, C#=6
        if (stringName === "G") {
            if (r === 0) return "0";
            if (r === 1 || r === 2) return "1";
            if (r === 3) return "2"; // Bb
            if (r === 4) return "3"; // B natural
            if (r === 5 || r === 6) return "4"; // C / C#
        }

        // C string no-shift stability:
        // C=0, Db/C#=1, D=2, Eb=3, E=4, F=5, F#=6
        if (stringName === "C") {
            if (r === 0) return "0";
            if (r === 1 || r === 2) return "1";
            if (r === 3) return "2"; // Eb
            if (r === 4) return "3"; // E
            if (r === 5 || r === 6) return "4"; // F / F#
        }

        // D string correction remains safe:
        // F# on D string should be 3, G/G# should be 4 unless the direct chromatic
        // G-Ab neighbor rule above applies.
        if (stringName === "D") {
            if (r === 0) return "0";
            if (r === 1 || r === 2) return "1";
            if (r === 3) return "2"; // F
            if (r === 4) return "3"; // F#
            if (r === 5 || r === 6) return "4"; // G/G#
        }

        // A string equivalent conservative mapping.
        if (stringName === "A") {
            if (r === 0) return "0";
            if (r === 1 || r === 2) return "1";
            if (r === 3) return "2"; // C
            if (r === 4) return "3"; // C#
            if (r === 5 || r === 6) return "4"; // D/D#
        }

        return defaultFinger;
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

        var checkedChords = 0;

        while (c.segment && checkedChords < lookaheadChords) {
            if (c.element && c.element.type == Element.CHORD) {
                checkedChords++;

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

    function estimateFingering(pitch, openStrings, lastFingerCode, cursor) {
        var bestString = "";
        var bestScore = 9999;
        var bestTrueOffset = 9999;
        var lastString = lastFingerCode && lastFingerCode.length > 0 ? lastFingerCode.charAt(0) : "";
        var higherComing = upcomingGoesHigher(cursor, pitch);

        for (var i = 0; i < openStrings.length; i++) {
            var openPitch = openStrings[i];

            if (pitch >= openPitch) {
                var offset = pitch - openPitch;
                var stringName = noteName(openPitch);

                var score = offset;

                // Mild continuity only. Do not force same-string reaching.
                if (stringName === lastString && offset <= 12) score -= 2;

                // Avoid very high stretches on lower strings when a higher string can do better.
                if (offset > 18) score += 8;

                // If the phrase continues upward, shift/setup earlier by preferring closer offsets.
                if (higherComing && offset <= 12) score -= 2;

                if (score < bestScore) {
                    bestScore = score;
                    bestString = stringName;
                    bestTrueOffset = offset;
                }
            }
        }

        if (bestString === "") return "X";

        var finger = noShiftFinger(bestString, bestTrueOffset);
        finger = frameCorrectedFinger(bestString, bestTrueOffset, finger, cursor);

        // New high-position rule:
        // Until thumb position is introduced, avoid using 4 above high A (A4, MIDI 69).
        // If the line continues upward, re-anchor with 1. Otherwise use 3 as the safer high-position finger.
        if (avoidFourthAboveHighA && pitch > avoidFourthAbovePitch && finger === "4") {
            finger = higherComing ? "1" : "3";
        }

        return bestString + finger;
    }

    function formatFingerForDisplay(fingerCode, lastFingerCode) {
        if (fingerCode === "" || fingerCode === "X") return fingerCode;

        var stringName = fingerCode.charAt(0);
        var fingerNumber = fingerCode.substr(1);
        var lastStringName = lastFingerCode && lastFingerCode.length > 0 ? lastFingerCode.charAt(0) : "";
        var showStringName = !hideStringNames && (!showStringOnlyOnChange || stringName !== lastStringName);

        if (stackStringAndFinger) return showStringName ? stringName + "\n" + fingerNumber : fingerNumber;
        return showStringName ? stringName + fingerNumber : fingerNumber;
    }

    function addFingerText(notes, textElement, lastFinger, cursor) {
        if (typeof lastFinger == "undefined") lastFinger = "";

        var labelLines = [];
        var newLastFinger = lastFinger;

        for (var i = 0; i < notes.length; i++) {
            var note = notes[i];
            if (skipTiedContinuations && isTiedContinuation(note)) continue;

            var fingerCode = estimateFingering(note.pitch, instrument(), lastFinger, cursor);

            if (skipRepeatedFingerings && fingerCode === lastFinger) {
                newLastFinger = fingerCode;
                lastFinger = fingerCode;
                continue;
            }

            var label = formatFingerForDisplay(fingerCode, lastFinger);
            if (showNoteNames) label = label + "\n" + fullNoteName(note.pitch);
            if (showPitch) label = label + "\n" + note.pitch;
            if (label.length > 0) labelLines.push(label);

            newLastFinger = fingerCode;
            lastFinger = fingerCode;
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
        if (!curScore) {
            Qt.quit();
            return;
        }

        var lastFinger = "";
        var startStaff;
        var endStaff;
        var endTick;
        var fullScore = false;

        var cursor = curScore.newCursor();
        cursor.rewind(1);

        if (!cursor.segment) {
            fullScore = true;
            startStaff = 0;
            endStaff = curScore.nstaves - 1;
        } else {
            startStaff = cursor.staffIdx;
            cursor.rewind(2);
            endTick = cursor.tick === 0 ? curScore.lastSegment.tick + 1 : cursor.tick;
            endStaff = cursor.staffIdx;
        }

        curScore.startCmd();

        for (var staff = startStaff; staff <= endStaff; staff++) {
            lastFinger = "";

            for (var voice = 0; voice < 4; voice++) {
                cursor.staffIdx = staff;
                cursor.voice = voice;
                cursor.rewind(fullScore ? 0 : 1);
                cursor.staffIdx = staff;
                cursor.voice = voice;

                while (cursor.segment && (fullScore || cursor.tick < endTick)) {
                    if (cursor.element && cursor.element.type == Element.CHORD) {
                        var chord = cursor.element;

                        var graceChords = chord.graceNotes;
                        for (var i = 0; i < graceChords.length; i++) {
                            var graceText = makeFingerTextElement();
                            graceText.offsetX = -2.5 * (graceChords.length - i);
                            lastFinger = addFingerText(graceChords[i].notes, graceText, lastFinger, cursor);
                            if (graceText.text.length > 0) cursor.add(graceText);
                        }

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
