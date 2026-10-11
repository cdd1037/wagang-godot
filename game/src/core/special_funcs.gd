class_name SpecialFuncs
extends RefCounted
## EEX op 0x71 特殊功能 (handler 0x436436, jump table 0x43646b, ids < 0x14):
##  0 / 4: EV[4088] = rand(EV[4088])  (0x43640e: u32 @0x55efe0 = EV base 0x55b000 + 0x3fe0)
##  5    : write byte EV[2699] to SAVEDATA\Niuniu.wa @0 (persistent system record)  (0x436502 → 0x41a1b0)

const NIUNIU := "user://niuniu.bin"
## Set once the file has the 环境设定 bytes: a file from before they were kept gets the shipped ones.
const NIUNIU_SEEDED := "user://niuniu_settings"


static func run(_host: ScriptHost, n: int) -> void:
	match n:
		0, 4:
			Mem.set_ev(4088, Rules.rand(Mem.ev(4088)))
		5:
			write_niuniu(0, Mem.ev(2699) & 0xff)
		_:
			push_warning("special_func %d not implemented" % n)


## The game ships SAVEDATA\Niuniu.wa (assets/data/niuniu.bin): 环境设定 bytes 1..5 and 0x6b with everything on,
## 讯息 快, 移动 普通, 升级显示能力成长 on and 花色３. A missing file starts as that one.
static func read_niuniu() -> PackedByteArray:
	var b := PackedByteArray()
	if FileAccess.file_exists(NIUNIU):
		b = FileAccess.get_file_as_bytes(NIUNIU)
	if b.size() < 108 or not FileAccess.file_exists(NIUNIU_SEEDED):
		var ship := FileAccess.get_file_as_bytes(Assets.path("data/niuniu.bin"))
		ship.resize(108)
		if b.is_empty():
			b = ship
		else:
			b.resize(108)
			for o in [1, 2, 3, 4, 5, 0x6b]:
				b[o] = ship[o]
		var f := FileAccess.open(NIUNIU, FileAccess.WRITE)
		if f:
			f.store_buffer(b)
			f.close()
			var m := FileAccess.open(NIUNIU_SEEDED, FileAccess.WRITE)
			if m:
				m.store_string("1")
	return b


static func write_niuniu(off: int, v: int) -> void:
	var b := read_niuniu()
	b[off] = v
	var f := FileAccess.open(NIUNIU, FileAccess.WRITE)
	if f:
		f.store_buffer(b)
