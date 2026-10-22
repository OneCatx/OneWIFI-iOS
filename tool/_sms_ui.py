import pathlib
p = pathlib.Path(r"E:\GQ\Ultra\ONEWIFI\android\lib\features\devices\presentation\device_detail_runtime_panel.dart")
t = p.read_text(encoding="utf-8")
if "smsStorage" not in t:
    needle = "        children: <Widget>[\n          const SizedBox(height: OneSpacing.small),\n          GlassTile("
    insert = """        children: <Widget>[
          if (device.smsStorage case final DeviceSmsStorage storage) ...<Widget>[
            GlassTile(
              child: Text(
                '模组短信 SM ${storage.sm.used}/${storage.sm.total} · ME ${storage.me.used}/${storage.me.total}',
              ),
            ),
            const SizedBox(height: OneSpacing.medium),
          ],
          const SizedBox(height: OneSpacing.small),
          GlassTile("""
    if needle in t:
        t = t.replace(needle, insert, 1)
        p.write_text(t, encoding="utf-8", newline="\n")
        print("sms ui added")
    else:
        print("needle missing")
else:
    print("already")
