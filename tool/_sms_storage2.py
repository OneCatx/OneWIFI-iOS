import pathlib
root = pathlib.Path(r"E:\GQ\Ultra\ONEWIFI\android")
dto_path = root/"lib/features/devices/data/device_dto.dart"
dto = dto_path.read_text(encoding="utf-8")
if "smsStorage" not in dto:
    dto = dto.replace(
        "    required this.runtime,\n    required this.esimSwitch,\n  });",
        "    required this.runtime,\n    required this.esimSwitch,\n    this.smsStorage,\n  });",
    )
    dto = dto.replace(
        "  final DeviceEsimSwitchDto esimSwitch;\n",
        "  final DeviceEsimSwitchDto esimSwitch;\n  final DeviceSmsStorage? smsStorage;\n",
    )
    anchor = "    final esimSwitch = DeviceEsimSwitchDto._fromData(data['esim_switch']);"
    if anchor in dto:
        dto = dto.replace(anchor, anchor + "\n    final smsStorage = _parseSmsStorage(data['sms_storage']);")
    dto = dto.replace(
        "      esimSwitch: esimSwitch,\n    );",
        "      esimSwitch: esimSwitch,\n      smsStorage: smsStorage,\n    );",
    )
    helper = """
DeviceSmsStorage? _parseSmsStorage(Object? value) {
  if (value == null) return null;
  try {
    final map = _shape.map(value);
    DeviceSmsMailbox box(Object? raw) {
      if (raw == null) return const DeviceSmsMailbox();
      final m = _shape.map(raw);
      return DeviceSmsMailbox(
        used: _shape.nonNegativeIntegralInt(m['used'] ?? 0),
        total: _shape.nonNegativeIntegralInt(m['total'] ?? 0),
      );
    }
    return DeviceSmsStorage(sm: box(map['sm']), me: box(map['me']));
  } catch (_) {
    return null;
  }
}
"""
    dto = dto + "\n" + helper
    dto_path.write_text(dto, encoding="utf-8", newline="\n")
    print("dto patched")
else:
    print("dto already")

repo_path = root/"lib/features/devices/data/device_repository.dart"
repo = repo_path.read_text(encoding="utf-8")
if "smsStorage: dto.smsStorage" not in repo:
    old = "esimSwitch: dto.esimSwitch"
    # find DeviceSnapshot construction
    if "esimSwitch:" in repo:
        # try common patterns
        for pat, rep in [
            ("      esimSwitch: dto.esimSwitch.toDomain(),\n    );", "      esimSwitch: dto.esimSwitch.toDomain(),\n      smsStorage: dto.smsStorage,\n    );"),
            ("    esimSwitch: dto.esimSwitch.toDomain(),\n  );", "    esimSwitch: dto.esimSwitch.toDomain(),\n    smsStorage: dto.smsStorage,\n  );"),
            ("      esimSwitch: _mapEsimSwitch(dto.esimSwitch),\n    );", "      esimSwitch: _mapEsimSwitch(dto.esimSwitch),\n      smsStorage: dto.smsStorage,\n    );"),
        ]:
            if pat in repo:
                repo = repo.replace(pat, rep)
                break
        else:
            # dump nearby
            idx = repo.find("esimSwitch:")
            print("NEAR", repo[idx-80:idx+200])
    repo_path.write_text(repo, encoding="utf-8", newline="\n")
    print("repo has", "smsStorage: dto.smsStorage" in repo_path.read_text(encoding="utf-8"))
else:
    print("repo already")
