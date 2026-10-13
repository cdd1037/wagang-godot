extends Node
## BGM (original CD-audio tracks, replaced by numbered MP3s) and sound effects.

## Every sound effect asked for (checks listen to it).
signal se_played(name: String)

var bgm_player: AudioStreamPlayer
var _se_players: Array[AudioStreamPlayer] = []
var current_track := -1
var _loop := true
var bgm_volume_db := -4.0
var se_volume_db := -2.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bgm_player = AudioStreamPlayer.new()
	bgm_player.volume_db = bgm_volume_db
	add_child(bgm_player)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = se_volume_db
		add_child(p)
		_se_players.append(p)


## Play CD track n (the game's track numbering; files are assets/audio/bgm/NN.mp3). 0x4745b1 records the track
## (GS+4) even while 听背景音乐 is off, and plays it only when it is on.
func play_bgm(track: int, loop := true) -> void:
	if track == current_track and bgm_player.playing:
		return
	current_track = track
	_loop = loop
	if not Settings.on(Settings.BGM):
		bgm_player.stop()
		return
	var s := Assets.audio("audio/bgm/%02d.mp3" % track)
	if s == null:
		bgm_player.stop()
		return
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = loop
	bgm_player.stream = s
	bgm_player.play()


func stop_bgm() -> void:
	current_track = -1
	bgm_player.stop()


## 环境设定 OK (0x41b92d): SE off stops the sound that plays; BGM off stops the music; then the recorded track is
## played again, from its start unless it is still playing.
func apply_switches() -> void:
	if not Settings.on(Settings.SE):
		stop_se()
	if not Settings.on(Settings.BGM):
		bgm_player.stop()
	elif current_track >= 0:
		play_bgm(current_track, _loop)


func stop_se() -> void:
	for p in _se_players:
		p.stop()
	SoundMap.stop_loop()


## name like "se00", "se_m_12", "se_e_03". Nothing plays while 听音效 is off (0x474777).
func play_se(name: String) -> void:
	se_played.emit(name)
	if not Settings.on(Settings.SE):
		return
	var s := Assets.audio("audio/se/%s.wav" % name.to_lower())
	if s == null:
		return
	for p in _se_players:
		if not p.playing:
			p.stream = s
			p.play()
			return
	_se_players[0].stream = s
	_se_players[0].play()


func se(n: int) -> void:
	play_se("se%02d" % n)


func se_m(n: int) -> void:
	play_se("se_m_%02d" % n)


func se_e(n: int) -> void:
	play_se("se_e_%02d" % n)
