//Clay Bailey
//CPSC432 Spring 2020 Assignment 5
(
s.boot;
s.options.memSize = 2.pow(20);
s.reboot;
s.waitForBoot({
	t = TempoClock.default;
	t.tempo = 2;

	// //load buffers
	~flute = Buffer.read(s, "sf/fluteLoop.wav".resolveRelative);//me playing a recorder
	~flute1 = Buffer.read(s, "sf/fluteFormer.wav".resolveRelative);//split into first and second half
	~flute2 = Buffer.read(s, "sf/fluteLatter.wav".resolveRelative);


	~oh = Buffer.read(s, "sf/oh.wav".resolveRelative);//excerpts from a throat singing clip from FreeSounds
	~ee = Buffer.read(s, "sf/ee.wav".resolveRelative);

	~question = Buffer.read(s, "sf/question1.wav".resolveRelative);//me speaking some quotes from various things
	~soseki = Buffer.read(s, "sf/soseki.wav".resolveRelative);
	~schizo = Buffer.read(s, "sf/schizo.wav".resolveRelative);

	~irChurchClose = Buffer.read(s, "sf/st_georges_close.wav".resolveRelative);//fft related bufs
	~irTunnel = Buffer.read(s, "sf/ir_purnode_tunnel_balloon_48k.wav".resolveRelative);
	~irTunnel.loadToFloatArray(action:{arg array; ~irTunnel.sendCollection(array.reverse)});//reverse ir
	s.sync;

	//fft prep
	~fftsize=4096;
	~bufsize = PartConv.calcBufSize(~fftsize, ~irTunnel);
	~irspectrumRev = Buffer.alloc(s, ~bufsize, 1);
	~irspectrumRev.preparePartConv(~irTunnel, ~fftsize);

	~bufsize = PartConv.calcBufSize(~fftsize, ~irChurchClose);
	~irspectrumBiwa = Buffer.alloc(s, ~bufsize, 1);
	~irspectrumBiwa.preparePartConv(~irChurchClose, ~fftsize);

	~bufsize = PartConv.calcBufSize(~fftsize, ~ee);
	~eespectrum = Buffer.alloc(s, ~bufsize, 1);
	~eespectrum.preparePartConv(~ee, ~fftsize);
	s.sync;

	//synthdefs

	//Wind and a Flute loop blended together using PV_SoftWipe
	SynthDef('wind', {arg frq = 0.7, ctr = 440, wid = 100, quiet = 0.3, lowcut = 5000, amp = 1, wipe = 0.99, pan = 0, gate = 1;
		//Randomness to make the wind sound natural
		var rand = LFNoise1.kr(frq, wid, ctr);
		var noise = WhiteNoise.ar(rand.linexp(ctr-wid, ctr+wid, quiet, 1));
		var band = BPF.ar(noise, rand, rand.reciprocal * 100);
		var wind = LPF.ar(band, rand.linexp(ctr-wid, ctr+wid, lowcut, 10000));

		var flute = Mix.ar(PlayBuf.ar(2, ~flute, loop: 1, doneAction:2));
		var rev = FreeVerb.ar(flute);//cheap reverb because i just want a little bit

		//blend the sounds
		var chainA = FFT(LocalBuf(2048),rev);
		var chainB = FFT(LocalBuf(2048),wind);

		var chain = PV_SoftWipe(chainA, chainB, Lag.kr(wipe, 30));

		var out = IFFT(chain).dup;
		var env = EnvGen.kr(Env.adsr(8,0,1,8,curve:'lin'),gate,doneAction: 2);//fade in/out
		Out.ar(0, Pan2.ar(out*amp, Lag.kr(pan,3))*env);

	}).add;

	//A 3-bank comb-filter resonator which sustains a note using PV_MagFreeze
	SynthDef('flutefreeze', {arg buf = 0, freq = 440, stop = 100, amp = 1, pan = 0,  gate=1;
		//using the flute sound
		var sig = Mix.ar(PlayBuf.ar(2,buf,BufRateScale.kr(buf),gate)*0.5);

		//resonator banks at approx 2nd and 3rd harmonic
		var res1 = CombC.ar(sig, 1, freq.reciprocal,2);
		var res2 = CombC.ar(sig, 1, (freq*2.02).reciprocal,1);
		var res3 = CombC.ar(sig, 1, (freq*2.98).reciprocal,1);
		var mix = Mix.ar([res1,res2,res3]);

		//freeze mags
		var chain = FFT(LocalBuf(2048),mix);
		var freezeEnv = EnvGen.kr(Env([0,0,1],[stop,100]),gate);//freeze after 'stop' seconds
		var freeze = PV_MagFreeze(chain, freezeEnv);
		var inv = IFFT(freeze);


		var env = EnvGen.kr(Env.asr,gate,doneAction: 2);
		Out.ar(0,Pan2.ar(inv*env*amp,pan));
	}).add;

	//pitched playback run through a PV_BrickWall filter
	SynthDef('throat', {arg buf = 0, gate = 1, freq = 127*2, amp = 1, dur = 1, wipe = 0;
		var env = EnvGen.kr(Env.adsr(0.4,0.3,0.8,0.2,1,2), gate, doneAction:2);
		var play = Mix.ar(PlayBuf.ar(2, buf, Lag.kr(freq.expexp(127,127*2,1,2,nil),1), gate, 25000, 1));

		var chain = FFT(LocalBuf(2048), play);
		var brick = PV_BrickWall(chain, wipe);
		var out = IFFT(brick);

		Out.ar(0, Pan2.ar(out*env*amp));
	}).add;

	//same string instrument as Midterm; some mods made to make it easier to run through fx Synths
	//Used partConv reverb with churchClose
	SynthDef('biwa', {|freq, t_gate = 1, amp = 0.1, brightness = 1, pan = 0, buf = 0|
		//indeces of the modulators are frequency dependent (lower->richer)
		var i1 = freq.cpsmidi.reciprocal*100;
		var i2 = freq.cpsmidi.reciprocal*100 * brightness;//arg allowing for dynamic change in timbre

		//ratio of carrier:mod1:mod2 approx. 1:3:4, with small offset to give it life
		var mod1 = SinOsc.ar(freq * 3.0172       ,  mul: freq * i1);
		var mod2 = SinOsc.ar(freq * 3.9463 + mod1,  mul: freq * i2);
		var car =  SinOsc.ar(freq          + mod2,  mul: amp      );

		//PURE MAGIC -- but a lot of it is frequency dependant
		var pluck = Pluck.ar(car, t_gate, freq.reciprocal, freq.reciprocal, freq.cpsmidi.reciprocal*60.0, 0.5);

		//filter env
		var filt = BPF.ar(pluck, Line.kr(freq*5,freq*3));

		//reverb
		var verb = PartConv.ar(filt*0.5, ~fftsize, buf, 0.5);
		var mix = DelayC.ar(filt, BufDur.ir(buf)) + (verb * 0.125);

		//fixing a memory allocation error -- what is an easier way to free Pluck.ar?
		FreeSelf.kr(TDelay.kr(Trig.kr(pluck), 10));

		Out.ar(0, Pan2.ar(mix, pan))
	}).add;

	//this is a vocoder that uses partconv and a saw wave to pitch the 'ee' vowel throat-sisging sample
	SynthDef('eesong',{arg freq = 440, gate = 1, amp = 1;
		var env = EnvGen.kr(Env.asr(releaseTime:0.4), gate, doneAction:2);
		var sig = Saw.ar(freq + Saw.ar(freq*2, mul: freq*0.2));
		var conv = PartConv.ar(sig, ~fftsize, ~eespectrum);
		Out.ar(0, Pan2.ar(conv*env*amp*0.006));
	}).add;

	//this is another apporoach to vocoding a vocal sample, using convolution
	SynthDef('saw',{arg freq, gate = 1 ;
		var env = EnvGen.kr(Env.asr(0.1, releaseTime:0.4), gate, doneAction:2);
		Out.ar(21, Saw.ar(freq, 0.3))
	}).add;
	SynthDef('vocode',{arg buf = 0, t_gate = 1, rate = 1, cut = 10000, amp = 1,pan=0,decay=0;
		var question = PlayBuf.ar(buf.numChannels, buf, rate, t_gate, loop:0, doneAction:2);
		var rev = FreeVerb.ar(question);
		var filt = HPF.ar(rev, cut);
		var in = In.ar(21);
		var conv = Convolution.ar(in, filt*10, 4096) - (filt*0.00);
		var verb = DelayC.ar(Decay.ar(conv,decay),decay,decay, add: conv);
		Out.ar(0, Pan2.ar(verb,pan)*amp);
	}).add;

	//the following drum sounds are made myself using designs found online at:
	//https://modeaudio.com/magazine/drum-synth-sound-design-kick-snare
	//https://www.soundonsound.com/techniques/practical-cymbal-synthesis
	~drumTune = 54;
	SynthDef('kick', {arg amp = 1, pan = 0.25;
		var bumpEnv = Env(times: [0.005, 0.005]);
		var bump = PinkNoise.ar(mul: bumpEnv.kr);

		var bodyEnv = Env(times: [0.018, 0.088]);
		var body = SinOsc.ar(~drumTune, mul: bodyEnv.kr(2));

		var mix = Mix.ar([bump * 0.3, body * 1]);

		var filt = BRF.ar(mix, 300, 0.5);

		Out.ar(0, Pan2.ar(filt * amp, pan));
	}).add;

	//I used a PV_EvenBin in this instrument to try to try to chop up the sound of the snare
	SynthDef('snare',
		{arg out=0,rq = 6, vel = 1, decay = 0.25, pos = 0, amp = 1, t_gate = 1,pan=0;
			//pos: position hit on drum; 0 = center, 1 = rim;
			var sustain = (decay * vel).explin(0.000001, decay, decay*0.5, decay);

			var clickEnv = Env(times: [0.002, 0.002]);
			var click = WhiteNoise.ar(mul: clickEnv.kr);

			var bodyEnv = Env(times: [0.006, 0.018]);
			var bodyFreq = (~drumTune * 2.sqrt) + (pos * 100);
			var body = SinOsc.ar(bodyFreq, mul: bodyEnv.kr);

			var snareEnv = Env([4, 1]*bodyFreq*9, [sustain]);
			var snareNoise = WhiteNoise.ar;
			var snareFilt = RLPF.ar(snareNoise, snareEnv.kr, rq);

			//Chopping up the snare
			var chain = FFT(LocalBuf(1024), snareFilt, 0.5, winsize: 128); // adjust the winsize to change the frame size
			var even = PV_EvenBin(chain);
			var snare = IFFT(even);

			var mixEnv = EnvGen.kr(Env(times: [0.003, sustain],curve:'cub'), t_gate, doneAction:2);
			var mix = Mix.ar([click * (vel.explin(0.001,1,0.1,0.2)), body * 0.5, snare * 10]) * mixEnv;

			Out.ar(out, Pan2.ar(mix * vel * amp,pan));
	}).add;

	//the 'special' arg is the carrier:modulator frequency ratio
	SynthDef('ride',{ arg frq = 5000, special = 2.187, i = 0.8, band = 8000, cut = 12000, amp = 1, t_gate = 1,dur = 1, pan = 0.25;

		var fmpul = Pulse.ar(frq + Pulse.ar(frq * special, mul: frq * i));
		var bpf = BPF.ar(fmpul, band, 0.1);
		var benv = Env.perc(0.01,0.1);
		var henv = Env([0,1,1,0],[0.004,0.080,dur-0.084],'cub');
		var hpf = HPF.ar(fmpul, cut);
		var mix = Mix.ar([bpf*benv.kr*10, hpf*henv.kr*2]);
		var menv = EnvGen.kr(Env.perc, t_gate, doneAction: 2);
		Out.ar(0, Pan2.ar(mix*menv*amp, pan));
	}).add;

	//same E.Piano as Midterm
	SynthDef('epiano', {|out=0, freq, gate = 1, amp = 1, pan = 0, fb = 1|

		//parameters
		var bellSinVol = 0.3;
		var bellFMVol = 0.5;
		var bellIndex = 0.732;

		var bodyVol = 0.4;
		var bodyIndex = 1;

		//panning and vibrato LFOs
		var freqVib = SinOsc.kr(Line.kr(0, 5), mul: Line.kr(0, freq*0.003), add:freq);//vibrato-modulated freq

		//the bell is comprised of an unprocessed sine tone, and a two-oscillator FM synth
		var bellSin = SinOsc.ar(freqVib, mul: bellSinVol);//pure sine

		var bellMod = SinOsc.ar(freq, mul: freq*bellIndex);//modulator
		var cFreq = freqVib*(2 pow: 4.0833);//carrier freq is 25 semitones higher
		var bellCar = SinOsc.ar(cFreq + bellMod, mul: bellFMVol);//
		var bellEnv = EnvGen.kr(Env.adsr(0.0016, 0.330, 0.022, 0.07, 0.83), gate, doneAction:2);
		var bell = Mix.ar([bellSin, bellCar])*bellEnv*0.2;

		//the body is a two-oscillator feedback FM synth
		var fdbk = LocalIn.ar(1);
		var bodyMod = SinOsc.ar(freq, mul: Line.kr(freq*bodyIndex, 0, 3.7));//mod index decreases over sus
		var bodyCar = SinOsc.ar(freqVib + (bodyMod + fdbk*fb), mul: bodyVol);//apply feedback coefficient
		var lout = LocalOut.ar(bodyCar);
		var bodyEnv = EnvGen.kr(Env.adsr(0.0016, 3, 0, 0.099, 0.83), gate, doneAction:2);
		var body = bodyCar*bodyEnv;

		var sig = LPF1.ar(Mix.ar([body, bell]), 1000);//filter out highest sidebands

		Out.ar(out, sig*amp);
	}).add;

	//FX Synths: I learned a good bit about when to code an effect into a synthdef and when to refactor it into its own synth
	//divide mags and phases by 3: featured in the 2nd section's keys
	SynthDef('magDiv',{arg out=0,pan=0,gate=1;
		var panLFO = LFTri.kr(4.5, mul: 0.2);//slight ping-ponging
		var env = Linen.kr(gate, 0.05, 1, 0.1, 2);
		var in = In.ar(out);//pfx
		var chain = FFT(LocalBuf(1024),in)
		.pvcollect(2048, {|mag, phase, index|

			[mag, phase] / 3;

		}, frombin: 0, tobin: 250, zeroothers: 0);
		var sig = IFFT(chain);
		Out.ar(0,Pan2.ar(sig*env,panLFO+pan));
	}).add;

	//random appearance/disappearance of bins; 3rd section keys
	SynthDef('LFMags',{arg out=0,pan=0,gate=1;
		var panLFO = LFTri.kr(4.5, mul: 0.2);//slight ping-ponging
		var env = Linen.kr(gate, 0.05, 1, 0.1, 2);
		var in = In.ar(out);//pfx
		var chain = FFT(LocalBuf(1024),in)
		.pvcollect(2048, {|mag, phase, index|

			if(LFNoise0.kr(10) > 0.5, mag, 0);

		}, frombin: 0, tobin: 250, zeroothers: 0);
		var sig = IFFT(chain);
		Out.ar(0,Pan2.ar(sig*env,panLFO+pan));
	}).add;

	//partconv on the irTunnel buffer in reverse: 2nd section snare
	SynthDef('reverseVerb',{arg out=0,pan=0,gate=1;
		var env = Linen.kr(gate, 0.05, 1, 0.1, 2);
		var in = Mix.ar(In.ar(out));//pfx
		var sig = PartConv.ar(in,~fftsize,~irspectrumRev);
		Out.ar(0,Pan2.ar(in+sig,pan,env));
	}).add;

	s.sync;

	//Pattterns: organized by synthdef
	~wind = Pmono('wind',
		'dur', Pseq([24],inf),
		'wipe', Pseq([0.99,0.125,0,-0.75,-0.85,-0.95,-1]),//change wind/flute mix
		'pan', Pseq((0!2)++(-0.7!5)),
		'amp',0.1
	);
	~justwind = Pbind('instrument','wind','wipe',1,'dur',Pseq([20]));//only play wind

	~throat = Pmono('throat',
		'root',9,'octave',3,'legato',0.9,
		'buf',~oh,'amp',0.5);
	~throat1 = Pbindf(~throat,
		'dur',Pseq([7,9]),
		'degree',Pseq([2,4]),
		'wipe',0.01);//hi-passed
	~throat2 = Pbindf(~throat,'amp',0.1,
		'dur',Pseq([7,5]),
		'degree',Pseq([[2,9],[4,8]]),
		'wipe',0.007);//less hi-passed
	~throat3a = Pbindf(~throat,'amp',0.1,
		'dur',Pseq([2,7,7]),
		'degree',Pseq([1,2,5]),
		'wipe',0);//no filtering
	~throat3b = Pbindf(~throat,'amp',0.1,
		'dur',Pseq([2,7,7]),
		'degree',Pseq([10,9,8]),
		'wipe',0);//no filtering
	~throatOut = Pbindf(~throat1,'dur',4,'degree',[2,9],'wipe',0);

	~string = Pbind(
		'instrument','biwa',
		'root',9,'octave',3,
		'buf',~irspectrumBiwa,//for reverb
		'dur',Pseq([8],2),
		'degree',Pseq([[9,6,5,3,-1],[10,9,6,5,2],]),
		'strum',0.1,
		'pan',Pseq([-0.3,0.3],inf));

	~fluteP1 = Pbind('instrument','flutefreeze',
		'buf',~flute1,
		'dur',Pseq([8]),
		'root',9,
		'octave',4,
		'degree',Pseq([3]),//resonator tuning
		'stop',1.5,//sustain using PV_magFreeze
		'amp',0.007*2,
		'pan',0.3);
	~fluteP2 = Pbind('instrument','flutefreeze',
		'buf',~flute2,
		'dur',Pseq([8]),
		'root',9,
		'octave',4,
		'degree',Pseq([0]),//resonator tuning
		'stop',100,//do not use PV_MagFreeze (100s too long to have effect)
		'amp',0.004*2,
		'pan',-0.5);
	~flutes = Pseq([~fluteP1,~fluteP2],2);

	//'special' used to change tone
	~cymbalIntro = Pbind('instrument','ride',
		'dur',Pseq(((0.125!4++Rest(0.5))!3).insert(2,0.25!4).flatten,),'amp',0.01,
		'special',Pseq([8,5,9,3].sqrt,inf),'pan',Pseq([0,0.5],inf));
	~cymbalStab = Pbindf(~cymbalIntro,
		'dur',Pseq(0.125!4++Rest(0.5)));
	~cymbal = Pbind('instrument','ride',
		'dur',Pseq([2],8),'amp',0.01,'pan',0.25);
	~cymbal2 = Pbind('instrument','ride',
		'dur',Pseq([1],16),'amp',0.005,
		'special',2.187,'pan',0.25);
	~cymbalFill = Pbind('instrument','ride',
		'dur',Pseq([2]),'amp',0.015,
		'special',2.333,'pan',0.25);
	~cymb = Pbind('instrument','ride',
		'dur',Pseq([0.5,0.25,0.25],16),'amp',0.01,
		'pan',0.25);
	~randCymb = Pbindf(~cymb,'amp',0.005,
		'special',Pbrown(2,4,0.073),'pan',Pseq([-0.5,0.5],inf));

	~presnare = Pbind('instrument','snare','dur',Pseq([Rest(2),2,Rest(2),2],2),'amp',0.2,'out',77);
	~snare = Pfx(~presnare,'reverseVerb','out',77,'pan',0.25);
	~snareFill = Pbind('instrument','snare',
		'dur',Pseq([0.25,0.75,0.25,0.75,]++(0.05!40)),
		'vel',Pseq([1,0.2,1,0.2]++((40..1)/80)),
		'pan',Pseq([-0.25,0.25],inf),
		'amp',0.2);

	~rhythmicMotif = [Rest(0.25),0.75,0.25,0.25,1,0.5,0.5,0.25,2.25,0.5,0.5,0.5,0.25,0.25];

	~kickRhythm = [Rest(0.25),1,1.25,1,0.25,2.25,0.5,1,0.5];//subtracted a few notes from the motif
	~kick1 = Pbind('instrument','kick','dur',Pseq(~kickRhythm,2),'amp',Pwhite(0.5,1.0)*0.3,'pan',0.25);
	~four =  Pbind('instrument', 'kick', 'dur', Pseq([1], 16),'amp',0.3,'pan',0.25);

	~melody = [Rest(0.25),[2,9],[2,1],[4,1],[5,2],6,2,4,5,[6,10],[5,11],[4,10],[5,9],[4,6]];
	~melodyP =Pbind('instrument','epiano',
		'amp',0.7,
		'out',36,'root',9,'octave',4,'strum',0.05,
		'dur',Pseq(~rhythmicMotif,2),
		'degree',Pseq(~melody,2));
	~meloA= Pseq(Array.fill(2,{|i|Pbindf(Pfx(~melodyP,'magDiv','out',36),'pan',[0,0.2][i],'amp',0.4)}));//i had trouble using a Pseq in a Pfx
	~meloB = Pseq(Array.fill(2,{|i|Pbindf(Pfx(~melodyP,'LFMags','out',36),'pan',[0,-0.3][i],'amp',0.3)}));
	~outro = Pfx(
		Pbind('instrument','epiano',
			'root',9,'octave',4,'out',36,
			'dur',Pseq([14,2,16]),'note',Pseq(([4,8,9,12]!2)++[[4,7,11,14]])
		),
	'LFMags','out',36,'amp',0.7);

	//vocal clips: the first pattern plays the clip and the second plays the vocoder
	//harmonic content determined stochastically
	~playQuestion1 = Pbind('instrument','vocode', 'buf',~question,'dur',Pseq([1]),
		'decay',0,'cut',10000,'amp',0.15);//high-passed to make it less boomy
	~playQuestion2 = Pbind('instrument', 'saw',
		'dur', Pseq([4],inf),
		'legato', 1,
		'octave', 4,
		'root',9,
		//stochastic
		'degree', Prand(Array.fill(7, {|i| 3.collect({|j| (0..7).wrapAt(i + (j*2))})}),inf));

	~playSoseki1 = Pbind('instrument','vocode',
		'buf',~soseki,'dur',Pseq([1]),
		'decay',0.2,'cut',7500,'amp',0.03,'pan',-0.4,);//give a bit more bottom
	~playSoseki2 = Pbind('instrument', 'saw',
		'dur', Pseq([4],inf),
		'legato', 1,
		'octave', 3,
		'root',4,
		// stochastic
		'degree', Prand(Array.fill(7, {|i| 3.collect({|j| (0..7).wrapAt(i + (j*2))})}),inf));

	~playSchizo1 = Pbind('instrument','vocode',
		'buf',~schizo,'dur',Pseq([1]),'rate',1.1,
		'decay',0,'cut',10000,'amp',0.1,'pan',0.15);
	~playSchizo2 = Pbind('instrument', 'saw',
		'dur', Pseq([4],inf),
		'legato', 1,
		'octave', 5,
		'root',5,
		// stochastic
		'degree', Prand(Array.fill(7, {|i| 3.collect({|j| (0..7).wrapAt(i + (j*2))})}),inf));

	~bassVox = Pmono('eesong',
		'amp', 0.2,
		'dur', Prand([4,Pseq([2,2]),Pseq([2,1,1])], 2),//stochastic
		'legato', 0.9,
		'root',9,
		'octave', 1,
		'pan',Pwhite(-1,1),
		'degree', Prand([-1,2,3,5,6,9],inf)//stochastic
	);

	//scoring
	~off = 68;//offset: when the rest of the song starts in relation to the wind/flute intro
	Ptpar([/**/
		//Ia. wind/flute; hi-passed throat singers
		0, ~wind,
		~off, Pseq([~throat1],3),
		16*1 + ~off, ~throat2,
		//IIa. drums, more low end on the throat singers
		16*2 + ~off - 4, ~cymbalIntro,
		16*2 + ~off - 2, Pseq([~throat3a],6),
		16*2 + ~off - 2, Pseq([~throat3b],6),
		16*2 + ~off, Pseq([~cymbal],2),
		16*2.5 + ~off, ~cymbalStab,
		16*2.75 + ~off + 1, Pseq([~cymbalStab],2),
		16*3 + ~off, Pseq([~snare],4),
		16*3 + ~off, ~cymbalStab,
		16*3.75 + ~off + 1, Pseq([~cymbalStab],2),
		16*4 + ~off - 4, ~snareFill,
		16*4 + ~off - 2, Pmono('ride','dur',Pseq([4]),'special',0.05),
		//IIb. drums, strings, vocoded flute, mags/3 fft keys
		16*4 + ~off, Pseq([~string],3),
		16*4 + ~off, Pseq([~cymbal2],3),
		16*4 + ~off, Pseq([~kick1],3),
		16*5 + ~off, ~meloA,
		16*5 + ~off + 1, ~flutes,
		//III. drums become more square, twangy cymbals, vocoded vox, random mags fft keys
		16*7 + ~off, ~justwind,
		16*7 + ~off, ~throatOut,
		16*7 + ~off - 1, Pbindf(~fluteP1,'pan',-0.3),
		16*7 + ~off, Pseq([~randCymb],6),
		16*7 + ~off, Pseq([~four],6),
		16*7.5 + ~off, ~playQuestion1,
		16*7.5 + ~off, ~playQuestion2,
		16*9 + ~off,  Pseq([~bassVox],10),
		16*10 + ~off, ~playSoseki1,
		16*10 + ~off, ~playSoseki2,
		16*11 + ~off, ~meloB,
		//Coda
		16*13 + ~off, ~outro,
		16*13 + ~off + 3.5, ~playSchizo1,
		16*13 + ~off + 3.5, ~playSchizo2,
		16*13 + ~off + 14, Pbind('instrument','kick','dur',Pseq(2!3)),
		16*13 + ~off + 16, Pmono('snare','dur',Pseq([2]),'decay',0.5,'amp',0.04),
		16*14 + ~off + 2, Pmono('ride','dur',Pseq([4]),'special',0.05),
	]).play;
});
)

s.freeAll