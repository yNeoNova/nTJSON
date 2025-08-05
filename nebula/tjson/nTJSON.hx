package nebula.tjson;

import sys.io.File;

using StringTools;

/**
 * nTJSON - A lightweight JSON parser and encoder for Haxe 4.3.3
 * 
 * Copyright (c) 2025 yNeoNova
 * Licensed under the Nebula License 1.0 (Attribution Required).
 * 
 * Usage of this software requires that credit to the authors be maintained
 * in all copies or substantial portions of this software.
 */

class nTJSON {
    public static var OBJECT_REFERENCE_PREFIX = "@~obRef#";

    /**
     * Parses a JSON string into a dynamic object or array.
     * @param json The JSON string to parse.
     * @param fileName Optional file name for error messages.
     * @param stringProcessor Optional function to process strings.
     */
    public static function parse(json:String, ?fileName:String="JSON Data", ?stringProcessor:String->Dynamic = null):Dynamic {
        var parser = new nTJSONParser(json, fileName, stringProcessor);
        return parser.doParse();
    }

    /**
     * Encodes a dynamic object or array into JSON string.
     * @param obj The object to encode.
     * @param style Encoding style ('fancy', 'simple' or custom EncodeStyle instance).
     * @param useCache Whether to cache references.
     */
    public static function encode(obj:Dynamic, ?style:Dynamic=null, ?useCache:Bool=true):String {
        var encoder = new nTJSONEncoder(useCache);
        return encoder.doEncode(obj, style);
    }

    /**
     * Saves an object encoded as JSON to a file.
     * @param obj The object to save.
     * @param path File path where JSON will be saved.
     * @param style Encoding style, default 'fancy'.
     */
    public static function saveToFile(obj:Dynamic, path:String, ?style:Dynamic = "fancy"):Void {
        var content = encode(obj, style);
        File.saveContent(path, content);
    }
}


/** Parser class for JSON */
class nTJSONParser {
    var pos:Int;
    var json:String;
    var lastSymbolQuoted:Bool;
    var fileName:String;
    var currentLine:Int;
    var cache:Array<Dynamic>;
    var floatRegex:EReg;
    var intRegex:EReg;
    var strProcessor:String->Dynamic;

    public function new(vjson:String, ?vfileName:String="JSON Data", ?stringProcessor:String->Dynamic=null) {
        json = vjson;
        fileName = vfileName;
        currentLine = 1;
        lastSymbolQuoted = false;
        pos = 0;
        floatRegex = ~/^-?[0-9]*\.[0-9]+$/;
        intRegex = ~/^-?[0-9]+$/;
        strProcessor = (stringProcessor == null ? defaultStringProcessor : stringProcessor);
        cache = [];
    }

    public function doParse():Dynamic {
        try {
            return switch (getNextSymbol()) {
                case '{': doObject();
                case '[': doArray();
                case s: convertSymbolToProperType(s);
            }
        } catch (e:String) {
            throw fileName + " on line " + currentLine + ": " + e;
        }
    }

    private function doObject():Dynamic {
        var o:Dynamic = {};
        var val:Dynamic = '';
        var key:String;
        var isClassOb:Bool = false;
        cache.push(o);
        while (pos < json.length) {
            key = getNextSymbol();
            if (key == "," && !lastSymbolQuoted) continue;
            if (key == "}" && !lastSymbolQuoted) {
                // Call TJ_unserialize if exists (optional)
                if (isClassOb && Reflect.hasField(o, "TJ_unserialize")) {
                    Reflect.callMethod(o, Reflect.field(o, "TJ_unserialize"), []);
                }
                return o;
            }

            var separator = getNextSymbol();
            if (separator != ":") throw "Expected ':' but got '" + separator + "'.";

            var v = getNextSymbol();

            if (key == "_hxcls") {
                if (v.startsWith("Date@")) {
                    o = Date.fromTime(Std.parseInt(v.substr(5)));
                } else {
                    var cls = Type.resolveClass(v);
                    if (cls == null) throw "Invalid class name - " + v;
                    o = Type.createEmptyInstance(cls);
                }
                cache.pop();
                cache.push(o);
                isClassOb = true;
                continue;
            }

            if (v == "{" && !lastSymbolQuoted) val = doObject();
            else if (v == "[" && !lastSymbolQuoted) val = doArray();
            else val = convertSymbolToProperType(v);

            Reflect.setField(o, key, val);
        }
        throw "Unexpected end of file. Expected '}'.";
    }

    private function doArray():Dynamic {
        var a:Array<Dynamic> = [];
        var val:Dynamic;
        while (pos < json.length) {
            val = getNextSymbol();
            if (val == "," && !lastSymbolQuoted) continue;
            else if (val == "]" && !lastSymbolQuoted) return a;
            else if (val == "{" && !lastSymbolQuoted) val = doObject();
            else if (val == "[" && !lastSymbolQuoted) val = doArray();
            else val = convertSymbolToProperType(val);
            a.push(val);
        }
        throw "Unexpected end of file. Expected ']'.";
    }

    private function convertSymbolToProperType(symbol):Dynamic {
        if (lastSymbolQuoted) {
            if (StringTools.startsWith(symbol, nTJSON.OBJECT_REFERENCE_PREFIX)) {
                var idx = Std.parseInt(symbol.substr(nTJSON.OBJECT_REFERENCE_PREFIX.length));
                return cache[idx];
            }
            return strProcessor(symbol);
        }
        if (looksLikeFloat(symbol)) return Std.parseFloat(symbol);
        if (looksLikeInt(symbol)) return Std.parseInt(symbol);
        var l = symbol.toLowerCase();
        if (l == "true") return true;
        if (l == "false") return false;
        if (l == "null") return null;
        return symbol;
    }

    private function looksLikeFloat(s:String):Bool {
        if (floatRegex.match(s)) return true;
        if (intRegex.match(s)) {
            var intStr = intRegex.matched(0);
            if (intStr.charCodeAt(0) == "-".charCodeAt(0)) return intStr > "-2147483648";
            else return intStr > "2147483647";
        }
        var f = Std.parseFloat(s);
        return f > 2147483647.0 || f < -2147483648.0;
    }

    private function looksLikeInt(s:String):Bool {
        return intRegex.match(s);
    }

    private function getNextSymbol() {
        lastSymbolQuoted = false;
        var c:String = '';
        var inQuote = false;
        var quoteType = "";
        var symbol = "";
        var inEscape = false;
        var inSymbol = false;
        var inLineComment = false;
        var inBlockComment = false;

        while (pos < json.length) {
            c = json.charAt(pos++);
            if (c == "\n" && !inSymbol) currentLine++;
            if (inLineComment) {
                if (c == "\n" || c == "\r") {
                    inLineComment = false;
                    pos++;
                }
                continue;
            }
            if (inBlockComment) {
                if (c == "*" && json.charAt(pos) == "/") {
                    inBlockComment = false;
                    pos++;
                }
                continue;
            }

            if (inQuote) {
                if (inEscape) {
                    inEscape = false;
                    switch (c) {
                        case '"': case "'": symbol += c; continue;
                        case "t": symbol += "\t"; continue;
                        case "n": symbol += "\n"; continue;
                        case "\\": symbol += "\\"; continue;
                        case "r": symbol += "\r"; continue;
                        case "/": symbol += "/"; continue;
                        case "u":
                            var hexValue = 0;
                            for (i in 0...4) {
                                if (pos >= json.length) throw "Unfinished UTF8 character";
                                var nc = json.charCodeAt(pos++);
                                hexValue = hexValue << 4;
                                if (nc >= 48 && nc <= 57) hexValue += nc - 48;
                                else if (nc >= 65 && nc <= 70) hexValue += 10 + nc - 65;
                                else if (nc >= 97 && nc <= 102) hexValue += 10 + nc - 97;
                                else throw "Not a hex digit";
                            }
                            symbol += String.fromCharCode(hexValue);
                            continue;
                        default:
                            throw "Invalid escape sequence '\\" + c + "'";
                    }
                } else {
                    if (c == "\\") {
                        inEscape = true;
                        continue;
                    }
                    if (c == quoteType) return symbol;
                    symbol += c;
                    continue;
                }
            } else if (c == "/") {
                var c2 = json.charAt(pos);
                if (c2 == "/") {
                    inLineComment = true;
                    pos++;
                    continue;
                } else if (c2 == "*") {
                    inBlockComment = true;
                    pos++;
                    continue;
                }
            }

            if (inSymbol) {
                if (c == ' ' || c == "\n" || c == "\r" || c == "\t" || c == ',' || c == ":" || c == "}" || c == "]") {
                    pos--;
                    return symbol;
                } else {
                    symbol += c;
                    continue;
                }
            } else {
                if (c == ' ' || c == "\t" || c == "\n" || c == "\r") continue;
                if (c == "{" || c == "}" || c == "[" || c == "]" || c == "," || c == ":") return c;
                if (c == '"' || c == "'") {
                    inQuote = true;
                    quoteType = c;
                    lastSymbolQuoted = true;
                    continue;
                } else {
                    inSymbol = true;
                    symbol = c;
                    continue;
                }
            }
        }
        if (inQuote) throw "Unexpected end of data. Expected (" + quoteType + ")";
        return symbol;
    }

    private function defaultStringProcessor(str:String):Dynamic {
        return str;
    }
}


/** Encoder class for JSON */
class nTJSONEncoder {
    var cache:Array<Dynamic>;
    var useCache:Bool;

    public function new(useCache:Bool = true) {
        this.useCache = useCache;
        if (useCache) cache = [];
    }

    public function doEncode(obj:Dynamic, ?style:Dynamic = null):String {
        if (!Reflect.isObject(obj)) throw "Provided object is not an object.";

        var st:EncodeStyle;
        if (Std.isOfType(style, EncodeStyle)) st = style;
        else if (style == "fancy") st = new FancyStyle();
        else st = new SimpleStyle();

        var buffer = new StringBuf();
        if (Std.isOfType(obj, Array) || Std.isOfType(obj, List)) {
            buffer.add(encodeIterable(obj, st, 0));
        } else if (Std.isOfType(obj, haxe.ds.StringMap)) {
            buffer.add(encodeMap(obj, st, 0));
        } else {
            cacheEncode(obj);
            buffer.add(encodeObject(obj, st, 0));
        }
        return buffer.toString();
    }

    private function encodeObject(obj:Dynamic, style:EncodeStyle, depth:Int):String {
        var buffer = new StringBuf();
        buffer.add(style.beginObject(depth));
        var fieldCount = 0;
        var fields:Array<String>;
        var dontEncodeFields:Array<String> = null;
        var cls = Type.getClass(obj);
        if (cls != null) {
            fields = Type.getInstanceFields(cls);
        } else {
            fields = Reflect.fields(obj);
        }

        switch (Type.typeof(obj)) {
            case TClass(c):
                var className = Type.getClassName(c);
                if (className == "Date") className += "@" + (cast obj : Date).getTime();
                if (fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
                else buffer.add(style.firstEntry(depth));
                buffer.add('"_hxcls"' + style.keyValueSeperator(depth));
                buffer.add(encodeValue(className, style, depth));

                if (Reflect.hasField(obj, "TJ_noEncode")) {
                    dontEncodeFields = Reflect.callMethod(obj, Reflect.field(obj, "TJ_noEncode"), []);
                }
            default:
        }

        for (field in fields) {
            if (dontEncodeFields != null && dontEncodeFields.indexOf(field) >= 0) continue;
            var value = Reflect.field(obj, field);
            var vStr = encodeValue(value, style, depth);
            if (vStr != null) {
                if (fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
                else buffer.add(style.firstEntry(depth));
                buffer.add('"' + field + '"' + style.keyValueSeperator(depth) + Std.string(vStr));
            }
        }
        buffer.add(style.endObject(depth));
        return buffer.toString();
    }

    private function encodeMap(obj:Map<Dynamic, Dynamic>, style:EncodeStyle, depth:Int):String {
        var buffer = new StringBuf();
        buffer.add(style.beginObject(depth));
        var fieldCount = 0;
        for (field in obj.keys()) {
            if (fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
            else buffer.add(style.firstEntry(depth));
            var value = obj.get(field);
            buffer.add('"' + field + '"' + style.keyValueSeperator(depth));
            buffer.add(encodeValue(value, style, depth));
        }
        buffer.add(style.endObject(depth));
        return buffer.toString();
    }

    private function encodeIterable(obj:Iterable<Dynamic>, style:EncodeStyle, depth:Int):String {
        var buffer = new StringBuf();
        buffer.add(style.beginArray(depth));
        var fieldCount = 0;
        for (value in obj) {
            if (fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
            else buffer.add(style.firstEntry(depth));
            buffer.add(encodeValue(value, style, depth));
        }
        buffer.add(style.endArray(depth));
        return buffer.toString();
    }

    private function cacheEncode(value:Dynamic):String {
        if (!useCache) return null;

        for (c in 0...cache.length) {
            if (cache[c] == value) return '"' + nTJSON.OBJECT_REFERENCE_PREFIX + c + '"';
        }
        cache.push(value);
        return null;
    }

    private function encodeValue(value:Dynamic, style:EncodeStyle, depth:Int):String {
        if (Std.isOfType(value, Int) || Std.isOfType(value, Float)) return Std.string(value);
        else if (Std.isOfType(value, Array) || Std.isOfType(value, List)) return encodeIterable(value, style, depth + 1);
        else if (Std.isOfType(value, haxe.ds.StringMap)) return encodeMap(value, style, depth + 1);
        else if (Std.isOfType(value, String)) return '"' + Std.string(value).replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\"", "\\\"") + '"';
        else if (Std.isOfType(value, Bool)) return Std.string(value);
        else if (Reflect.isObject(value)) {
            var ret = cacheEncode(value);
            if (ret != null) return ret;
            return encodeObject(value, style, depth + 1);
        } else if (value == null) return "null";
        else return null;
    }
}


/** Encoding style interface */
interface EncodeStyle {
    public function beginObject(depth:Int):String;
    public function endObject(depth:Int):String;
    public function beginArray(depth:Int):String;
    public function endArray(depth:Int):String;
    public function firstEntry(depth:Int):String;
    public function entrySeperator(depth:Int):String;
    public function keyValueSeperator(depth:Int):String;
}


/** Simple no-format style */
class SimpleStyle implements EncodeStyle {
    public function new() {}

    public function beginObject(depth:Int):String return "{";
    public function endObject(depth:Int):String return "}";
    public function beginArray(depth:Int):String return "[";
    public function endArray(depth:Int):String return "]";
    public function firstEntry(depth:Int):String return "";
    public function entrySeperator(depth:Int):String return ",";
    public function keyValueSeperator(depth:Int):String return ":";
}


/** Fancy style with indentation and new lines */
class FancyStyle implements EncodeStyle {
    public var tab(default, null):String;

    public function new(tab:String = "    ") {
        this.tab = tab;
        charTimesNCache = [""];
    }

    public function beginObject(depth:Int):String return "{\n";
    public function endObject(depth:Int):String return "\n" + charTimesN(depth) + "}";
    public function beginArray(depth:Int):String return "[\n";
    public function endArray(depth:Int):String return "\n" + charTimesN(depth) + "]";
    public function firstEntry(depth:Int):String return charTimesN(depth + 1) + " ";
    public function entrySeperator(depth:Int):String return "\n" + charTimesN(depth + 1) + ",";
    public function keyValueSeperator(depth:Int):String return " : ";

    private var charTimesNCache:Array<String>;

    private function charTimesN(n:Int):String {
        return if (n < charTimesNCache.length) {
            charTimesNCache[n];
        } else {
            charTimesNCache[n] = charTimesN(n - 1) + tab;
            charTimesNCache[n];
        }
    }
}
