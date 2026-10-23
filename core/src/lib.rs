use serde::{Deserialize, Serialize};
use std::ffi::{c_char, CStr, CString};

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
pub struct Time {
    pub value: i64,
    pub timescale: i32,
}

impl Time {
    fn valid(self) -> bool {
        self.value >= 0 && self.timescale > 0
    }
    fn compare(self, other: Self) -> std::cmp::Ordering {
        (i128::from(self.value) * i128::from(other.timescale))
            .cmp(&(i128::from(other.value) * i128::from(self.timescale)))
    }
    fn end(self, duration: Self) -> Result<Self, String> {
        let scale = i64::from(self.timescale) * i64::from(duration.timescale);
        let value = i128::from(self.value) * i128::from(duration.timescale)
            + i128::from(duration.value) * i128::from(self.timescale);
        let mut divisor = value;
        let mut remainder = i128::from(scale);
        while remainder != 0 {
            let next = divisor % remainder;
            divisor = remainder;
            remainder = next;
        }
        Ok(Self {
            value: i64::try_from(value / divisor).map_err(|_| "time overflow")?,
            timescale: i32::try_from(i128::from(scale) / divisor)
                .map_err(|_| "timescale overflow")?,
        })
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Media {
    pub id: u64,
    pub path: String,
    pub duration: Time,
    pub width: i32,
    pub height: i32,
    pub frame_rate: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Clip {
    pub id: u64,
    pub media_id: u64,
    pub position: Time,
    pub source_start: Time,
    pub duration: Time,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Track {
    pub id: u64,
    pub clips: Vec<Clip>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Project {
    pub version: u32,
    pub next_id: u64,
    pub media: Vec<Media>,
    pub track: Track,
}

impl Default for Project {
    fn default() -> Self {
        Self {
            version: 1,
            next_id: 1,
            media: vec![],
            track: Track {
                id: 0,
                clips: vec![],
            },
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "command")]
pub enum Command {
    #[serde(rename = "project.create")]
    Create,
    #[serde(rename = "project.open")]
    Open { path: String },
    #[serde(rename = "project.save")]
    Save { path: String },
    #[serde(rename = "media.import")]
    Import {
        path: String,
        duration: Time,
        width: i32,
        height: i32,
        frame_rate: f64,
    },
    #[serde(rename = "timeline.add_clip")]
    Add { media_id: u64, position: Time },
    #[serde(rename = "timeline.trim_clip")]
    Trim {
        clip_id: u64,
        source_start: Time,
        duration: Time,
    },
    #[serde(rename = "timeline.move_clip")]
    Move { clip_id: u64, position: Time },
    #[serde(rename = "timeline.remove_clip")]
    Remove { clip_id: u64 },
}

impl Project {
    fn validate(&self) -> Result<(), String> {
        if self.version != 1 || self.next_id == 0 || self.track.id != 0 {
            return Err("unsupported or invalid project".into());
        }
        let mut identifiers = std::collections::HashSet::new();
        for media in &self.media {
            if media.id == 0
                || media.id >= self.next_id
                || !identifiers.insert(media.id)
                || media.path.is_empty()
                || !media.duration.valid()
                || media.duration.value == 0
                || media.width <= 0
                || media.height <= 0
                || !media.frame_rate.is_finite()
                || media.frame_rate <= 0.0
            {
                return Err("invalid media metadata".into());
            }
        }
        for clip in &self.track.clips {
            if clip.id == 0
                || clip.id >= self.next_id
                || !identifiers.insert(clip.id)
                || !clip.position.valid()
                || !clip.source_start.valid()
                || !clip.duration.valid()
                || clip.duration.value == 0
            {
                return Err("invalid clip".into());
            }
            let media = self
                .media
                .iter()
                .find(|media| media.id == clip.media_id)
                .ok_or("missing media")?;
            if clip
                .source_start
                .end(clip.duration)?
                .compare(media.duration)
                .is_gt()
            {
                return Err("trim exceeds source duration".into());
            }
            clip.position.end(clip.duration)?;
        }
        for (index, clip) in self.track.clips.iter().enumerate() {
            for other in self.track.clips.iter().skip(index + 1) {
                if clip
                    .position
                    .compare(other.position.end(other.duration)?)
                    .is_lt()
                    && other
                        .position
                        .compare(clip.position.end(clip.duration)?)
                        .is_lt()
                {
                    return Err("clips overlap on the video track".into());
                }
            }
        }
        Ok(())
    }

    pub fn execute(&mut self, command: Command) -> Result<(), String> {
        let mut candidate = self.clone();
        match command {
            Command::Create => candidate = Self::default(),
            Command::Open { path } => {
                candidate = serde_json::from_slice(
                    &std::fs::read(path).map_err(|error| error.to_string())?,
                )
                .map_err(|error| error.to_string())?;
            }
            Command::Save { path } => {
                self.validate()?;
                let destination = std::path::Path::new(&path);
                let parent = destination
                    .parent()
                    .filter(|path| !path.as_os_str().is_empty())
                    .unwrap_or(std::path::Path::new("."));
                let temporary = parent.join(format!(
                    ".camtasia-{}-{}.tmp",
                    std::process::id(),
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map_err(|error| error.to_string())?
                        .as_nanos()
                ));
                let result = (|| -> Result<(), String> {
                    use std::io::Write;
                    let mut file = std::fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(&temporary)
                        .map_err(|error| error.to_string())?;
                    file.write_all(
                        &serde_json::to_vec_pretty(self).map_err(|error| error.to_string())?,
                    )
                    .map_err(|error| error.to_string())?;
                    file.sync_all().map_err(|error| error.to_string())?;
                    std::fs::rename(&temporary, destination).map_err(|error| error.to_string())
                })();
                if result.is_err() {
                    let _ = std::fs::remove_file(temporary);
                }
                return result;
            }
            Command::Import {
                path,
                duration,
                width,
                height,
                frame_rate,
            } => {
                candidate.media.push(Media {
                    id: candidate.next_id,
                    path,
                    duration,
                    width,
                    height,
                    frame_rate,
                });
                candidate.next_id = candidate
                    .next_id
                    .checked_add(1)
                    .ok_or("identifier overflow")?;
            }
            Command::Add { media_id, position } => {
                let media = candidate
                    .media
                    .iter()
                    .find(|media| media.id == media_id)
                    .ok_or("unknown media")?;
                candidate.track.clips.push(Clip {
                    id: candidate.next_id,
                    media_id,
                    position,
                    source_start: Time {
                        value: 0,
                        timescale: 1,
                    },
                    duration: media.duration,
                });
                candidate.next_id = candidate
                    .next_id
                    .checked_add(1)
                    .ok_or("identifier overflow")?;
            }
            Command::Trim {
                clip_id,
                source_start,
                duration,
            } => {
                let clip = candidate
                    .track
                    .clips
                    .iter_mut()
                    .find(|clip| clip.id == clip_id)
                    .ok_or("unknown clip")?;
                clip.source_start = source_start;
                clip.duration = duration;
            }
            Command::Move { clip_id, position } => {
                candidate
                    .track
                    .clips
                    .iter_mut()
                    .find(|clip| clip.id == clip_id)
                    .ok_or("unknown clip")?
                    .position = position;
            }
            Command::Remove { clip_id } => {
                if !candidate.track.clips.iter().any(|clip| clip.id == clip_id) {
                    return Err("unknown clip".into());
                }
                candidate.track.clips.retain(|clip| clip.id != clip_id);
            }
        }
        candidate.validate()?;
        *self = candidate;
        Ok(())
    }
}

#[no_mangle]
pub extern "C" fn editor_create() -> *mut Project {
    Box::into_raw(Box::new(Project::default()))
}

#[no_mangle]
pub unsafe extern "C" fn editor_destroy(handle: *mut Project) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn editor_execute(
    handle: *mut Project,
    request: *const c_char,
) -> *mut c_char {
    let response = std::panic::catch_unwind(std::panic::AssertUnwindSafe(
        || -> Result<serde_json::Value, String> {
            let project = handle.as_mut().ok_or("null editor handle")?;
            if request.is_null() {
                return Err("null request".into());
            }
            let command = serde_json::from_str(
                CStr::from_ptr(request)
                    .to_str()
                    .map_err(|error| error.to_string())?,
            )
            .map_err(|error| error.to_string())?;
            project.execute(command)?;
            serde_json::to_value(project).map_err(|error| error.to_string())
        },
    ));
    let json = match response {
        Ok(Ok(project)) => serde_json::json!({ "project": project }),
        Ok(Err(error)) => serde_json::json!({ "error": error }),
        Err(_) => serde_json::json!({ "error": "internal core panic" }),
    };
    CString::new(json.to_string())
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn editor_free(response: *mut c_char) {
    if !response.is_null() {
        drop(CString::from_raw(response));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn time(value: i64) -> Time {
        Time {
            value,
            timescale: 1,
        }
    }
    fn loaded() -> Project {
        let mut project = Project::default();
        project
            .execute(Command::Import {
                path: "/tmp/fixture.mp4".into(),
                duration: time(4),
                width: 320,
                height: 240,
                frame_rate: 30.0,
            })
            .expect("import");
        project
            .execute(Command::Add {
                media_id: 1,
                position: time(0),
            })
            .expect("add");
        project
    }
    #[test]
    fn rational_arithmetic() {
        assert_eq!(
            Time {
                value: 1,
                timescale: 3
            }
            .end(Time {
                value: 1,
                timescale: 6
            })
            .expect("sum"),
            Time {
                value: 1,
                timescale: 2
            }
        );
        assert_eq!(
            Time {
                value: 30,
                timescale: 30
            }
            .compare(time(1)),
            std::cmp::Ordering::Equal
        );
    }
    #[test]
    fn trim_move_delete() {
        let mut project = loaded();
        project
            .execute(Command::Trim {
                clip_id: 2,
                source_start: time(1),
                duration: time(2),
            })
            .expect("trim");
        project
            .execute(Command::Move {
                clip_id: 2,
                position: time(3),
            })
            .expect("move");
        assert_eq!(project.track.clips[0].source_start, time(1));
        assert_eq!(project.track.clips[0].position, time(3));
        project
            .execute(Command::Remove { clip_id: 2 })
            .expect("remove");
        assert!(project.track.clips.is_empty());
    }
    #[test]
    fn invalid_edits_are_atomic() {
        let mut project = loaded();
        let before = serde_json::to_string(&project).expect("serialize");
        assert!(project
            .execute(Command::Trim {
                clip_id: 2,
                source_start: time(3),
                duration: time(2)
            })
            .is_err());
        assert!(project
            .execute(Command::Add {
                media_id: 1,
                position: time(1)
            })
            .is_err());
        assert!(project
            .execute(Command::Move {
                clip_id: 2,
                position: Time {
                    value: 0,
                    timescale: 0
                }
            })
            .is_err());
        assert_eq!(before, serde_json::to_string(&project).expect("serialize"));
    }
    #[test]
    fn save_reopen() {
        let mut project = loaded();
        let path = std::env::temp_dir()
            .join(format!("editor-test-{}.json", std::process::id()))
            .to_string_lossy()
            .into_owned();
        project
            .execute(Command::Save { path: path.clone() })
            .expect("save");
        let mut reopened = Project::default();
        reopened
            .execute(Command::Open { path: path.clone() })
            .expect("open");
        assert_eq!(
            serde_json::to_string(&project).expect("serialize"),
            serde_json::to_string(&reopened).expect("serialize")
        );
        std::fs::remove_file(path).expect("cleanup");
    }
    #[test]
    fn ffi_handles_errors() {
        unsafe {
            let request = CString::new("{}").expect("request");
            let response = editor_execute(std::ptr::null_mut(), request.as_ptr());
            assert!(CStr::from_ptr(response)
                .to_str()
                .expect("response")
                .contains("null editor handle"));
            editor_free(response);
        }
    }
}
