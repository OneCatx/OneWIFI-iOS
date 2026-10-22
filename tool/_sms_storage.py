import pathlib, re
root = pathlib.Path(r"E:\GQ\Ultra\ONEWIFI\android")

# DeviceSmsStorage on DeviceSnapshot
dom = (root/"lib/features/devices/domain/device.dart").read_text(encoding="utf-8")
if "DeviceSmsStorage" not in dom:
    insert = '''
final class DeviceSmsMailbox {
  const DeviceSmsMailbox({this.used = 0, this.total = 0});
  final int used;
  final int total;
}

final class DeviceSmsStorage {
  const DeviceSmsStorage({
    this.sm = const DeviceSmsMailbox(),
    this.me = const DeviceSmsMailbox(),
  });
  final DeviceSmsMailbox sm;
  final DeviceSmsMailbox me;
}

'''
    dom = dom.replace("final class DeviceFleet {", insert + "final class DeviceFleet {")
    # add field to DeviceSnapshot
    dom = dom.replace(
        "    required this.runtime,\n    this.esimSwitch = const DeviceEsimSwitch.idle(),\n  });",
        "    required this.runtime,\n    this.esimSwitch = const DeviceEsimSwitch.idle(),\n"
        "    this.smsStorage,\n  });",
    )
    dom = dom.replace(
        "  final DeviceRuntime runtime;\n  final DeviceEsimSwitch esimSwitch;\n",
        "  final DeviceRuntime runtime;\n  final DeviceEsimSwitch esimSwitch;\n"
        "  final DeviceSmsStorage? smsStorage;\n",
    )
    dom = dom.replace(
        "      runtime: runtime,\n      esimSwitch: esimSwitch,\n    );",
        "      runtime: runtime,\n      esimSwitch: esimSwitch,\n"
        "      smsStorage: smsStorage,\n    );",
    )
    (root/"lib/features/devices/domain/device.dart").write_text(dom, encoding="utf-8", newline="\n")
    print("domain sms_storage added")

# dto - need DeviceSnapshotDto and mapping to domain - find toDomain or similar
dto = (root/"lib/features/devices/data/device_dto.dart").read_text(encoding="utf-8")
print("sms_storage in dto", "sms_storage" in dto)
# find where DeviceSnapshot( is constructed from dto
repo = (root/"lib/features/devices/data/device_repository.dart").read_text(encoding="utf-8")
idx = repo.find("DeviceSnapshot(")
print(repo[idx:idx+900] if idx>=0 else "no DeviceSnapshot in repo")
