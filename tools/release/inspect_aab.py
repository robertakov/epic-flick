"""Inspect a Google Play AAB without bundletool: decodes base/manifest/AndroidManifest.xml (aapt2 proto XmlNode)
and lists package, versions, SDKs, debuggable flag, permissions and native ABIs.
usage: python -I tools/release/inspect_aab.py <bundle.aab>"""
import sys
import zipfile


def varint(b, i):
    r = s = 0
    while True:
        x = b[i]; i += 1
        r |= (x & 0x7F) << s; s += 7
        if x < 0x80:
            return r, i


def fields(b):
    i, out = 0, []
    while i < len(b):
        key, i = varint(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = varint(b, i)
        elif wt == 2:
            ln, i = varint(b, i); v = b[i:i + ln]; i += ln
        elif wt == 5:
            v = b[i:i + 4]; i += 4
        elif wt == 1:
            v = b[i:i + 8]; i += 8
        else:
            raise ValueError(wt)
        out.append((f, v))
    return out


def element(node):  # XmlNode: 1=element
    for f, v in fields(node):
        if f == 1:
            return v
    return None


def walk(node, depth=0, path=""):
    el = element(node)
    if el is None:
        return
    name, attrs, kids = "", {}, []
    for f, v in fields(el):
        if f == 3:
            name = v.decode()
        elif f == 4:
            an, av, prim = "", "", None
            for af, avv in fields(v):
                if af == 2: an = avv.decode()
                elif af == 3: av = avv.decode()
                elif af == 6:  # compiled item -> prim(7) int values
                    for cf, cv in fields(avv):
                        if cf == 7:
                            for pf, pv in fields(cv):
                                if isinstance(pv, int): prim = pv
            attrs[an] = av if av != "" else prim
        elif f == 5:
            kids.append(v)
    yield path + "/" + name, attrs
    for k in kids:
        yield from walk(k, depth + 1, path + "/" + name)


z = zipfile.ZipFile(sys.argv[1])
man = z.read("base/manifest/AndroidManifest.xml")
perms = []
for p, a in walk(man):
    if p == "/manifest":
        print("package:", a.get("package"), "| versionCode:", a.get("versionCode"), "| versionName:", a.get("versionName"))
    elif p.endswith("/uses-sdk"):
        print("minSdk:", a.get("minSdkVersion"), "| targetSdk:", a.get("targetSdkVersion"))
    elif p.endswith("/application"):
        print("application debuggable:", a.get("debuggable", "absent (release)"))
    elif p.endswith("/uses-permission"):
        perms.append(a.get("name"))
print("permissions:", perms)
print("native ABIs:", sorted({n.split("/")[2] for n in z.namelist() if n.startswith("base/lib/")}))
print("dex files:", [n for n in z.namelist() if n.endswith(".dex")])
print("entries:", len(z.namelist()), "| zip test:", z.testzip() or "OK")
