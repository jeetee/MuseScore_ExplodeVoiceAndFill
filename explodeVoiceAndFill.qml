//=============================================================================
//  Extract a 2nd voice onto a staff from an 'a2'-style notated staff
//  Copyright (C) 2017 Johan Temmerman (jeetee)
//=============================================================================
import QtQuick 2.0
import MuseScore 1.0

MuseScore {
      menuPath: "Plugins.ExplodeVoiceAndFill"
      version:  "0.0.1"
      description: qsTr("Split out voices according to 'a2'-style")

      Timer {
            //moving right after copy doesn't work
            //I guestimate that the move somehow happens concurrent with the processing of the copy command
            //by making the move a timed (even by 0ms) function, we allow the copy event to be processed fully first
            id: yieldForCopy
            interval: 0 //since timer is synched with requestAnimationFrame, the resulting time is likely 16ms
            repeat: false
      }
      Timer {
            //moving right after paste doesn't work
            //I guestimate that the move somehow happens concurrent with the processing of the paste command
            //by making the move a timed (even by 0ms) function, we allow the paste event to be processed fully first
            id: yieldForPaste
            interval: 0 //since timer is synched with requestAnimationFrame, the resulting time is likely 16ms
            repeat: false
      }

      onRun: {
            if (!curScore) {
                  console.log(qsTranslate("QMessageBox", "No score open.\nThis plugin requires an open score to run.\n"));
                  Qt.quit();
            }

            console.log('Analysing voice 2');
            //currently a fixed track in test score
            var myVoice1Track = 4;
            var myVoice2Track = 5;
            var targetVoice1Track = 8;

            var voice2dataRanges = [];
            var currentVoice2dataRange = null;//{ 'from': {'tick': null, 'seg': null}, 'till': {'tick': null, 'seg': null}};

            var track = myVoice2Track;
            
            var segment = curScore.firstSegment(128/*ChordRest*/);
            while (segment) {
                  console.log("segment: " + segment + "  type " + segmentTypeToString(segment.segmentType) + ' (' + segment.segmentType + ')');
                  var element = segment.elementAt(myVoice2Track);
                  if (element && element.duration) {
                        var type     = element.type;
                        var duration = element.duration;
                        var durationString = ' ' + duration.numerator + '/' + duration.denominator + ' ' + duration.ticks;
                        console.log(segment.tick + ' ' + elementTypeToString(type) + ' (' + type + ')' + durationString);

                        //found an element, consider this voice filled with data
                        if ((currentVoice2dataRange !== null)
                         && (currentVoice2dataRange.till.tick === segment.tick)) {
                              //this segment extends the current data range
                              currentVoice2dataRange.till.tick = segment.tick + element.duration.ticks;
                              currentVoice2dataRange.till.seg = segment;
                        }
                        else {
                              //new dataRange
                              if (currentVoice2dataRange !== null) { //save previous range
                                    voice2dataRanges.push(currentVoice2dataRange);
                              }
                              currentVoice2dataRange = {
                                    'from': {
                                          'tick': segment.tick,
                                          'seg': segment
                                    },
                                    'till': {
                                          'tick': segment.tick + element.duration.ticks,
                                          'seg': segment
                                    }
                              };
                        }
                  }

                  segment = segment.next;
            }
            //final range?
            if (currentVoice2dataRange !== null) {
                  voice2dataRanges.push(currentVoice2dataRange);
            }

            console.log('\n\nVoice 2 data found in');
            for (var dr = 0; dr < voice2dataRanges.length; ++dr) {
                  console.log(voice2dataRanges[dr].from.tick + '\t' + voice2dataRanges[dr].from.seg + '\t' + voice2dataRanges[dr].till.tick + '\t' + voice2dataRanges[dr].till.seg);
            }

            console.log('\n\nstarting copy of voice 1');

            var pasteFunc = null;
            var afterPasteFunc = null;
            var copyInBetweenRange = (function(dr) {
                  console.log('copyInBetweenRange: ' + dr);
                  if (pasteFunc !== null) {
                        yieldForCopy.triggered.disconnect(pasteFunc);
                  }
                  selectRange(
                        myVoice1Track,
                        ((dr > 0)? voice2dataRanges[dr - 1].till.tick : 0),
                        ((dr < voice2dataRanges.length)? voice2dataRanges[dr].from.tick : -1)
                  );
                  //TODO validate range using cursor?
                  cmd("copy");
                  //connect seems to create an automatic closure anyway, so we'll have to recreate this function each loop
                  pasteFunc = (function() {
                        console.log('pasting for range ' + dr);
                        if (afterPasteFunc !== null) {
                              yieldForPaste.triggered.disconnect(afterPasteFunc);
                        }
                        selectRange(
                              targetVoice1Track,
                              ((dr > 0)? voice2dataRanges[dr - 1].till.tick : 0),
                              ((dr < voice2dataRanges.length)? voice2dataRanges[dr].from.tick : -1)
                        );
                        cmd("paste");
                        afterPasteFunc = (function () {
                              console.log('afterPaste ' + dr);
                              //call next range if needed
                              if (dr < voice2dataRanges.length) {
                                    copyInBetweenRange(dr + 1);
                              }
                              else { //the end - cleanup
                                    yieldForCopy.triggered.disconnect(pasteFunc);
                                    yieldForPaste.triggered.disconnect(afterPasteFunc);
                                    cmd("escape"); //de-select
                                    Qt.quit(); //done
                              }
                        });
                        yieldForPaste.triggered.connect(afterPasteFunc);
                        yieldForPaste.start();
                  });
                  yieldForCopy.triggered.connect(pasteFunc);
                  yieldForCopy.start();
            });
            //kick off the start of the recurring loop logic
            copyInBetweenRange(0);
      }


      function selectRange(track, startTick, endTick) {
            console.log('Selecting on track ' + track + ' from ' + startTick + ' till ' + endTick);

            //navigate to start of score
            cmd("first-element"); //clef
            cmd("next-chord"); //chord-rest
            //figure out how many tracks are actually present at this spot, as next-track only moves through tracks that have data
            var segment = curScore.firstSegment(128/*ChordRest*/);
            for (var t = track; t-- > 0; ) {
                  if (segment.elementAt(t)) {
                        cmd("next-track");
                  }
            }

            //move to the starting position
            while (segment && (segment.tick < startTick)) {
                  if ((segment.segmentType === 0x0080 /*ChordRest*/)
                   && (segment.elementAt(track)) //only move forward in our track if we have the actual element in our track
                     ) {
                        cmd("next-chord");
                  }
                  segment = segment.next;
            }

            //select it
            cmd("select-next-chord");
            cmd("select-prev-chord");

            //select range
            if (endTick !== -1) {
                  while (segment && (segment.tick < endTick)) {
                        if ((segment.segmentType === 0x0080 /*ChordRest*/)
                         && (segment.elementAt(track)) //only move forward in our track if we have the actual element in our track
                           ) {
                              cmd("select-next-chord");
                        }
                        segment = segment.next;
                  }
                  cmd("select-prev-chord"); //we will select one item too far, compensate
            }
            else {
                  cmd("select-end-score");
            }
      }

	function segmentTypeToString(segType) {
		var segmentTypes = Object.freeze({
			0x0000: 'Invalid',
			0x0001: 'Clef',
			0x0002: 'KeySig',
			0x0004: 'Ambitus',
			0x0008: 'TimeSig',
			0x0010: 'StartRepeatBarLine',
			0x0020: 'BarLine',
			0x0040: 'Breath',
			0x0080: 'ChordRest',
			0x0100: 'EndBarLine',
			0x0200: 'KeySigAnnounce',
			0x0400: 'TimeSigAnnounce'
		});
		return segmentTypes[segType];
	}

	function elementTypeToString(elType) {
		var elementTypes = Object.freeze([
			'Invalid',
			'Symbol',
			'Text',
			'Instrument Name',
			'Slur Segment',
			'Staff Lines',
			'Bar Line',
			'Stem Slash',
			'Line',

			'Arpeggio',
			'Accidental',
			'Stem',
			'Note',
			'Clef',
			'Keysig',
			'Ambitus',
			'Timesig',
			'Rest',
			'Breath',

			'Repeat Measure',
			'Image',
			'Tie',
			'Articulation',
			'Chordline',
			'Dynamic',
			'Beam',
			'Hook',
			'Lyrics',
			'Figured Bass',

			'Marker',
			'Jump',
			'Fingering',
			'Tuplet',
			'Tempo Text',
			'Staff Text',
			'Rehearsal Mark',
			'Instrument Change',
			'Harmony',
			'Fret Diagram',
			'Bend',
			'Tremolobar',
			'Volta',
			'Hairpin segment',
			'Ottava segment',
			'Trill segment',
			'Textline segment',
			'Volta segment',
			'Pedal segment',
			'Lyricsline segment',
			'Glissando segment',
			'Layout Break',
			'Spacer',
			'Staff State',
			'Ledger Line',
			'Notehead',
			'Notedot',
			'Tremolo',
			'Measure',
			'Selection',
			'Lasso',
			'Shadow Note',
			'Tab Duration Symbol',
			'FSymbol',
			'Page',
			'Hairpin',
			'Ottava',
			'Pedal',
			'Trill',
			'Textline',
			'Noteline',
			'Lyricsline',
			'Glissando',
			'Bracket',

			'Segment',
			'System',
			'Compound',
			'Chord',
			'Slur',
			'Element',
			'Element list',
			'Staff list',
			'Measure list',
			'Hbox',
			'Vbox',
			'Tbox',
			'Fbox',
			'Icon',
			'Ossia',
			'Bagpipe Embellishment',

			'MAXTYPE'
		]);
		return elementTypes[elType];
	}

}
