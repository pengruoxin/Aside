import glob
import json
for path in glob.glob("dist/smoke/*.ips"):
    with open(path) as file:
        content = file.read()
    try:
        _, rest = content.split("\n", 1)
        data = json.loads(rest)
        print("Crash:", path, data.get("exception"), data.get("termination"))
        index = data.get("faultingThread", 0)
        images = data.get("usedImages", [])
        for frame in data.get("threads", [])[index].get("frames", [])[:20]:
            image = images[frame.get("imageIndex", 0)]
            print(image.get("name"), frame.get("symbol"), frame.get("symbolLocation"))
    except Exception as error:
        print("Cannot summarize crash:", error)
