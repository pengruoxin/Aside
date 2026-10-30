#!/usr/bin/env python3
"""Bundle Homebrew-built dynamic libraries; consumers need no Homebrew installation."""
import pathlib
import shutil
import subprocess
import sys

binary = pathlib.Path(sys.argv[1]).resolve()
frameworks = pathlib.Path(sys.argv[2]).resolve()
licenses = pathlib.Path(sys.argv[3]).resolve()
frameworks.mkdir(parents=True, exist_ok=True)
licenses.mkdir(parents=True, exist_ok=True)
brew = pathlib.Path(subprocess.check_output(["brew", "--prefix"], text=True).strip())
seen = {}
pending = [(binary, binary)]

def dependencies(path):
    return [line.strip().split(" (")[0] for line in subprocess.check_output(["otool", "-L", str(path)], text=True).splitlines()[1:]]

def resolve(name, source):
    if name.startswith("@loader_path/"):
        return (source.parent / name[len("@loader_path/"):]).resolve()
    if name.startswith("@rpath/"):
        basename = pathlib.Path(name).name
        for candidate in [source.parent / basename, brew / "lib" / basename]:
            if candidate.exists():
                return candidate.resolve()
        raise RuntimeError("Cannot resolve dependency: " + name)
    return pathlib.Path(name).resolve()

while pending:
    output, source = pending.pop()
    for name in dependencies(source):
        if name.startswith(("/System/", "/usr/lib/")) or "libswift" in name:
            continue
        actual = resolve(name, source)
        if not actual.is_file():
            raise RuntimeError("Missing dependency: " + str(actual))
        bundled = frameworks / actual.name
        if str(actual) not in seen:
            seen[str(actual)] = bundled
            shutil.copy2(actual, bundled)
            subprocess.run(["install_name_tool", "-id", "@rpath/" + actual.name, str(bundled)], check=True)
            pending.append((bundled, actual))
            parts = actual.parts
            if "Cellar" in parts:
                i = parts.index("Cellar")
                root = pathlib.Path(*parts[:i+3])
                for license_file in root.glob("*"):
                    if license_file.is_file() and license_file.name.lower().startswith(("license", "licence", "copying", "copyright")):
                        dest = licenses / (parts[i+1] + "-" + license_file.name)
                        shutil.copy2(license_file, dest)
        subprocess.run(["install_name_tool", "-change", name, "@rpath/" + actual.name, str(output)], check=True)

for path in [binary, *frameworks.glob("*.dylib")]:
    lines = subprocess.check_output(["otool", "-l", str(path)], text=True).splitlines()
    for i, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH":
            value = lines[i+2].strip().split(" (")[0].removeprefix("path ")
            if value.startswith(("/opt/homebrew/", "/usr/local/")):
                subprocess.run(["install_name_tool", "-delete_rpath", value, str(path)], check=True)
    subprocess.run(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", str(path)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(path)], check=True)
    for name in dependencies(path):
        if name.startswith(("/opt/homebrew/", "/usr/local/")):
            raise RuntimeError("Unbundled library dependency: " + name)

print("Bundled", len(seen), "libraries with local dependency paths.")
