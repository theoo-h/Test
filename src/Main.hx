import haxe.ds.StringMap;
import haxe.ds.Vector;
import haxe.Timer;

// 2D float vector storage indexed by hashed string IDs
// Optimized for extremely hot lookup paths (modifiers)
@:noDebug
final class PercentArray {
    // Table size must be power of two
    static inline var TABLE_BITS:Int = 14; // 16384 slots
    static inline var TABLE_SIZE:Int = 1 << TABLE_BITS;
    static inline var TABLE_MASK:Int = TABLE_SIZE - 1;

    private var vector:Vector<Vector<Float>>;
    private var idCache:StringMap<Int>;

    public function new() {
        vector = new Vector<Vector<Float>>(TABLE_SIZE);
        idCache = new StringMap<Int>();
    }

    // 32-bit hash (fast, good enough for engine keys)
    @:noDebug @:noCompletion
    inline private function hash32(key:String):Int {
        var h:Int = 0;
        var len = key.length;
        for (i in 0...len) {
            h = h * 31 + StringTools.unsafeCodeAt(key, i);
        }
        return h;
    }

    // Resolve string key to table index (cached)
    @:noDebug
    inline private function resolveId(key:String):Int {
        var id = idCache.get(key);
        if (id == null) {
            id = hash32(key) & TABLE_MASK;
            idCache.set(key, id);
        }
        return id;
    }

    // ---------- Public API ----------

    // User-facing (string-based)
    @:noDebug
    inline public function get(key:String):Vector<Float>
        return vector.get(resolveId(key));

    @:noDebug
    inline public function set(key:String, value:Vector<Float>):Void
        vector.set(resolveId(key), value);

    // Engine-facing (hot path)
    @:noDebug
    inline public function getUnsafe(id:Int):Vector<Float>
        return vector.get(id);

    @:noDebug
    inline public function setUnsafe(id:Int, value:Vector<Float>):Void
        vector.set(id, value);

    // Optional: expose ID for pre-resolution
    @:noDebug
    inline public function id(key:String):Int
        return resolveId(key);

    // ---------- Debug collision detection ----------
    #if debug
    private var reverse:haxe.ds.IntMap<String> = new haxe.ds.IntMap();

    public function validateKey(key:String):Void {
        var id = hash32(key) & TABLE_MASK;
        var prev = reverse.get(id);
        if (prev != null && prev != key) {
            throw 'PercentArray hash collision: "$key" vs "$prev"';
        }
        reverse.set(id, key);
    }
    #end
}

class Main {
    static inline var ITERATIONS = 1_000_000;
    static inline var MOD_COUNT = 20;
    static inline var GETS_PER_MOD = 6;

    static function main() {
        trace("Warming up...");
        warmup();

        trace("Running benchmarks...");
        benchStringMap();
        benchPercentArray();
    }

    static function warmup() {
        for (i in 0...200_000) {}
    }

    // --------------------------------------------------
    // StringMap benchmark
    // --------------------------------------------------
    static function benchStringMap() {
        var map = new StringMap<Vector<Float>>();
        var keys = new Array<String>();

        for (i in 0...MOD_COUNT) {
            var k = "mod" + i;
            keys.push(k);
            map.set(k, vec());
        }

        var start = Timer.stamp();
        var sum = 0.0;

        for (i in 0...ITERATIONS) {
            for (m in 0...MOD_COUNT) {
                var key = keys[m];
                for (g in 0...GETS_PER_MOD) {
                    var v = map.get(key);
                    sum += v[0];
                }
            }
        }

        var elapsed = Timer.stamp() - start;
        trace("StringMap time: " + elapsed + "s (sum=" + sum + ")");
    }

    // --------------------------------------------------
    // PercentArray benchmark
    // --------------------------------------------------
    static function benchPercentArray() {
        var pa = new PercentArray();
        var ids = new Array<Int>();

        for (i in 0...MOD_COUNT) {
            var k = "mod" + i;
            pa.set(k, vec());
            ids.push(pa.id(k)); // pre-resolve
        }

        var start = Timer.stamp();
        var sum = 0.0;

        for (i in 0...ITERATIONS) {
            for (m in 0...MOD_COUNT) {
                var id = ids[m];
                for (g in 0...GETS_PER_MOD) {
                    var v = pa.getUnsafe(id);
                    sum += v[0];
                }
            }
        }

        var elapsed = Timer.stamp() - start;
        trace("PercentArray time: " + elapsed + "s (sum=" + sum + ")");
    }

    static inline function vec():Vector<Float> {
        var v = new Vector<Float>(2);
        v[0] = 1.0;
        v[1] = 0.5;
        return v;
    }
}
