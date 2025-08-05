nTJSON — Nebula TJSON Parser

**nTJSON** is a modern and extensible JSON parser and encoder written in Haxe.

It supports flexible and non-standard JSON syntax with:
- object references
- comments
- string unescaping
- class reconstruction
- custom formatting styles

Inspired by TJSON, it's ideal for game configuration files, modding data, and dynamic runtime object loading.

---

## Features

- Custom object deserialization (`_hxcls`, `TJ_unserialize`)
- Reuses object references to prevent duplication
- Fancy or simple formatting styles
- ompatible with `Dynamic`, `Array`, `Map`, `StringMap`, `Date`, and basic types
- Accepts comments (`//`, `/* */`) and trailing commas
- scaped characters (`\n`, `\uXXXX`, etc.) are properly parsed
- Single-file solution (no external dependencies)

---

## Installation

Install Directly from GitHub:

```bash
haxelib git nTJSON https://github.com/yNeoNova/nTJSON.git
```

Or, you can use [Haxe Module Manager](https://lib.haxe.org/p/hmm/)
```json
{
    "dependencies": [
    {
      "name": "nTJSON",
      "type": "git",
      "url": "https://github.com/yNeoNova/nTJSON.git",
      "ref": "main",
      "dir": null
    }
  ]
}
```
 

And Add this to `build.hxml`
```hxml
-lib nTJSON
```

---

Example Usage

```Haxe
import nebula.tjson.nTJSON;

class Main {
    static function main() {
        var json = '
        {
            // A character example
            "name": "Neo",
            "level": 5,
            "active": true,
            "tags": ["hero", "android"],
            "stats": {
                "speed": 8.5,
                "power": 7.2
            }
        }';

        var obj = nTJSON.parse(json);
        trace(obj.name); // Neo

        var encoded = nTJSON.encode(obj, "fancy");
        trace(encoded);
    }
}
```

Output:
```json
{
    "name" : "Neo",
    "level" : 5,
    "active" : true,
    "tags" : [
        "hero",
        "android"
    ],
    "stats" : {
        "speed" : 8.5,
        "power" : 7.2
    }
}
```

---

License – Nebula License

This software is open and free to use in personal or commercial projects.

> However, attribution is required. You must credit yNeoNova  in your project’s LICENSE, or about section.


If your project has no LICENSE file, include a comment or credit visibly in your source code.

By using this software, you agree to comply with this rule.

---

Credits

Developed by yNeoNova.

If you use this library, let us know or star the repository

