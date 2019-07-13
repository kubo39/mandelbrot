import core.stdc.stdlib : exit;
import std.complex;
import std.conv : to, ConvException;
import std.parallelism : parallel;
import std.range : chunks;
import std.stdio;
import std.typecons : Nullable, Tuple, tuple;

import imagefmt : write_image;

Nullable!uint escapeTime(Complex!double c, uint limit) @nogc nothrow pure @safe
{
    auto z = complex(0.0, 0.0);
    foreach (i; 0 .. limit)
    {
        z = z * z + c;
        if ((z.re * z.re + z.im * z.im) > 4.0)
            return typeof(return)(i);
    }
    return (typeof(return)).init;
}

alias Pair(T) = Nullable!(Tuple!(T, T));

Pair!T parsePair(T, char separator)(string s) pure @safe if (__traits(isArithmetic, T))
{
    import std.string : indexOf;

    immutable index = s.indexOf(separator);
    if (index == -1)
        return (typeof(return)).init;
    try
    {
        T l = s[0 .. index].to!T;
        T r = s[index + 1 .. $].to!T;
        return typeof(return)(tuple(l, r));
    }
    catch (ConvException) return (typeof(return)).init;
}

pure @safe unittest
{
    import std.meta : AliasSeq;
    foreach (T; AliasSeq!(int, long, uint, ulong))
    {
        assert(parsePair!(T, ',')("").isNull);
        assert(parsePair!(T, ',')("10,").isNull);
        assert(parsePair!(T, ',')("10,20").get() == tuple(10, 20));
        assert(parsePair!(T, ',')("10,20xy").isNull);
    }
    foreach (T; AliasSeq!(float, double))
    {
        assert(parsePair!(T, 'x')("0.5x").isNull);
        assert(parsePair!(T, 'x')("0.5x1.5").get() == tuple(0.5, 1.5));
    }
}

Nullable!(Complex!double) parseComplex(string s) pure @safe
{
    immutable pair = parsePair!(double, ',')(s);
    if (pair.isNull) return (typeof(return)).init;
    return typeof(return)(complex(pair.expand));
}

pure @safe unittest
{
    assert(parseComplex("1.25,-0.0625").get() == complex(1.25, -0.0625));
    assert(parseComplex(",-0.0625").isNull);
}

Complex!double pixelToPoint(T)(Tuple!(T, T) bounds, Tuple!(T, T) pixel,
                               Complex!double upperLeft, Complex!double lowerRight) @nogc pure nothrow @safe
    if (__traits(isIntegral, T))
{
    immutable width = lowerRight.re - upperLeft.re;
    immutable height = upperLeft.im - lowerRight.im;
    return complex(upperLeft.re + pixel[0] * width / bounds[0],
                   upperLeft.im - pixel[1] * height / bounds[1]);
}

@nogc pure nothrow @safe unittest
{
    assert(pixelToPoint(tuple(100, 100), tuple(25, 75),
                        complex(-1.0, 1.0), complex(1.0, -1.0))
           == complex(-0.5, -0.5));
}

void render(T)(ref ubyte[] pixels, Tuple!(T, T) bounds,
               Complex!double upperLeft, Complex!double lowerRight) @nogc pure nothrow @safe
    if (__traits(isIntegral,T))
in { assert(pixels.length == bounds[0] * bounds[1]); }
do
{
    foreach (row; 0 .. bounds[1])
    {
        foreach (column; 0 .. bounds[0])
        {
            immutable point = pixelToPoint!T(bounds, tuple(column, row),
                                             upperLeft, lowerRight);
            immutable count = escapeTime(point, 255);
            pixels[row * bounds[0] + column] =
                count.isNull ? 0 : cast(ubyte)(255 - count.get()); /* ensure count.get <= 255 */
        }
    }
}

int writeImage(string filename, const ubyte[] pixels, Tuple!(int, int) bounds) nothrow @nogc
{
    return write_image(filename, bounds.expand, pixels);
}

version(unittest) { void main() {} }
else
{
int main(string[] args)
{
    if (args.length != 5)
    {
        stderr.writeln("Usage: mandelbrot FILE PIXELS UPPERLEFT LOWERRIGHT");
        stderr.writefln("Example %s mandel.png 1000x750 -1.20,0.35 -1,0.20",
                        args[0]);
        exit(1);
    }
    immutable bounds = parsePair!(int, 'x')(args[2]).get();
    immutable upperLeft = parseComplex(args[3]).get();
    immutable lowerRight = parseComplex(args[4]).get();
    auto pixels = new ubyte[bounds[0] * bounds[1]];

    auto bands = pixels.chunks(bounds[0]);
    foreach (top, band; parallel(bands))
    {
        auto bandBounds = tuple(cast() bounds[0], 1);
        immutable bandUpperLeft = pixelToPoint(bounds, tuple(0, top.to!int),
                                               upperLeft, lowerRight);
        immutable bandLowerRight = pixelToPoint(bounds,
                                                tuple(cast() bounds[0], top.to!int + 1),
                                                upperLeft, lowerRight);
        render(band, bandBounds, bandUpperLeft, bandLowerRight);
    }
    return writeImage(args[1], pixels, bounds);
}
}
