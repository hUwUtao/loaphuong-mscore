use std::path::PathBuf;
use std::sync::Arc;
use std::time::SystemTime;

use nih_plug::prelude::*;
use std::num::NonZeroU32;

struct Loaphuong {
	params: Arc<LoaphuongParams>,

	// WAV state
	wav_data: Vec<f32>,
	wav_sample_rate: f32,
	wav_channels: u16,

	// File watching
	wav_path: PathBuf,
	last_mtime: Option<SystemTime>,
}

#[derive(Params)]
struct LoaphuongParams {
	#[id = "gain"]
	pub gain: FloatParam,

	#[id = "reload"]
	pub reload: BoolParam,
}

impl Default for LoaphuongParams {
	fn default() -> Self {
		Self {
			gain: FloatParam::new(
				"Gain",
				1.0,
				FloatRange::Linear { min: 0.0, max: 2.0 },
			)
			.with_unit("x")
			.with_step_size(0.01),

			reload: BoolParam::new("Reload", false),
		}
	}
}

impl Default for Loaphuong {
	fn default() -> Self {
		let wav_path = std::env::var("LOAPHUONG_WAV_PATH")
			.map(PathBuf::from)
			.unwrap_or_else(|_| {
				let home = std::env::var("HOME")
					.or_else(|_| std::env::var("USERPROFILE"))
					.unwrap_or_else(|_| "/tmp".to_string());
				PathBuf::from(home).join(".cache/loaphuong/render.wav")
			});

		let mut plugin = Self {
			params: Arc::new(LoaphuongParams::default()),
			wav_data: Vec::new(),
			wav_sample_rate: 48000.0,
			wav_channels: 2,
			wav_path,
			last_mtime: None,
		};
		plugin.reload_wav();
		plugin
	}
}

impl Loaphuong {
	fn reload_wav(&mut self) {
		self.wav_data.clear();
		let path = &self.wav_path;

		if !path.exists() {
			return;
		}

		let Ok(metadata) = path.metadata() else { return };
		self.last_mtime = metadata.modified().ok();

		let Ok(reader) = hound::WavReader::open(path) else { return };
		let spec = reader.spec();

		self.wav_sample_rate = spec.sample_rate as f32;
		self.wav_channels = spec.channels;

		match spec.sample_format {
			hound::SampleFormat::Float => {
				self.wav_data = reader
					.into_samples::<f32>()
					.filter_map(|s| s.ok())
					.collect();
			}
			hound::SampleFormat::Int => {
				let max = match spec.bits_per_sample {
					8 => i8::MAX as f32,
					16 => i16::MAX as f32,
					24 => 8388607.0,
					32 => i32::MAX as f32,
					_ => i16::MAX as f32,
				};
				self.wav_data = reader
					.into_samples::<i32>()
					.filter_map(|s| s.ok())
					.map(|s| s as f32 / max)
					.collect();
			}
		}
	}

	fn maybe_reload(&mut self) {
		if self.params.reload.value() {
			self.reload_wav();
			return;
		}

		let Ok(metadata) = self.wav_path.metadata() else { return };
		let mtime = match metadata.modified() {
			Ok(t) => t,
			Err(_) => return,
		};

		if self.last_mtime.map_or(true, |last| mtime != last) {
			self.reload_wav();
		}
	}
}

impl Plugin for Loaphuong {
	const NAME: &'static str = "Loaphuong";
	const VENDOR: &'static str = "hUwUtao";
	const URL: &'static str = "https://github.com/hUwUtao/loaphuong-mscore";
	const EMAIL: &'static str = "";
	const VERSION: &'static str = env!("CARGO_PKG_VERSION");

	const AUDIO_IO_LAYOUTS: &'static [AudioIOLayout] = &[AudioIOLayout {
		main_input_channels: None,
		main_output_channels: NonZeroU32::new(2),
		aux_input_ports: &[],
		aux_output_ports: &[],
		names: PortNames::const_default(),
	}];

	const MIDI_INPUT: MidiConfig = MidiConfig::None;
	const SAMPLE_ACCURATE_AUTOMATION: bool = false;

	type SysExMessage = ();
	type BackgroundTask = ();

	fn params(&self) -> Arc<dyn Params> {
		self.params.clone()
	}

	fn initialize(
		&mut self,
		_audio_io_layout: &AudioIOLayout,
		_buffer_config: &BufferConfig,
		_context: &mut impl InitContext<Self>,
	) -> bool {
		self.reload_wav();
		true
	}

	fn process(
		&mut self,
		buffer: &mut Buffer,
		_aux: &mut AuxiliaryBuffers,
		context: &mut impl ProcessContext<Self>,
	) -> ProcessStatus {
		self.maybe_reload();

		let transport = context.transport();
		let gain = self.params.gain.value();

		if !transport.playing || self.wav_data.is_empty() {
			for channel_samples in buffer.iter_samples() {
				for s in channel_samples {
					*s = 0.0;
				}
			}
			return ProcessStatus::Normal;
		}

		let project_rate = transport.sample_rate;
		let wav_channels = self.wav_channels as usize;
		let pos_samples = match transport.pos_samples() {
			Some(p) => p,
			None => {
				for channel_samples in buffer.iter_samples() {
					for s in channel_samples {
						*s = 0.0;
					}
				}
				return ProcessStatus::Normal;
			}
		};

		// Map transport position to WAV sample position
		let wav_pos_base = pos_samples as f64 * self.wav_sample_rate as f64 / project_rate as f64;

		for (sample_idx, mut channel_samples) in buffer.iter_samples().enumerate() {
			let wav_idx = (wav_pos_base + sample_idx as f64) as usize;

			for (ch, s) in channel_samples.iter_mut().enumerate() {
				let wav_ch = if wav_channels > 1 && ch < wav_channels {
					ch
				} else if wav_channels > 0 {
					0
				} else {
					*s = 0.0;
					continue;
				};

				let src = wav_idx * wav_channels + wav_ch;
				if src < self.wav_data.len() {
					*s = self.wav_data[src] * gain;
				} else {
					*s = 0.0;
				}
			}
		}

		ProcessStatus::Normal
	}
}

impl Vst3Plugin for Loaphuong {
	const VST3_CLASS_ID: [u8; 16] = *b"LoaphuongV1_____";
	const VST3_SUBCATEGORIES: &'static [Vst3SubCategory] = &[Vst3SubCategory::Instrument];
}

impl ClapPlugin for Loaphuong {
	const CLAP_ID: &'static str = "com.huwutao.loaphuong";
	const CLAP_DESCRIPTION: Option<&'static str> = Some("Vietnamese vocal synthesis playback");
	const CLAP_MANUAL_URL: Option<&'static str> = Some(Self::URL);
	const CLAP_SUPPORT_URL: Option<&'static str> = None;
	const CLAP_FEATURES: &'static [ClapFeature] = &[
		ClapFeature::Instrument,
		ClapFeature::Stereo,
	];
}

nih_export_vst3!(Loaphuong);
nih_export_clap!(Loaphuong);
