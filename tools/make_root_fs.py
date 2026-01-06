#! /usr/bin/env python3
import tarfile

if __name__ == "__main__":
    with tarfile.open("rootfs.tar", "w") as t:
        opt_dir = tarfile.TarInfo("opt")
        opt_dir.mtime = 0
        opt_dir.type = tarfile.DIRTYPE
        opt_dir.mode = 0o755
        opt_dir.uid = 0
        opt_dir.gid = 0
        opt_dir.uname = "root"
        opt_dir.gname = "root"
        t.addfile(opt_dir)
        setting_dir = tarfile.TarInfo("opt/setting")
        setting_dir.mtime = 0
        setting_dir.mode = 0o1777
        setting_dir.type = tarfile.DIRTYPE
        setting_dir.uid = 0
        setting_dir.gid = 0
        setting_dir.uname = "root"
        setting_dir.gname = "root"
        t.addfile(setting_dir)
