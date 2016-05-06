using Base.Test
import Base: tuple_type_cons, tuple_type_head, tuple_type_tail, in, ==, isless, convert,
             length, eltype, start, next, done, show

eltypes(::Type{Tuple{}}) = Tuple{}
eltypes{T<:Tuple}(::Type{T}) =
    tuple_type_cons(eltype(tuple_type_head(T)), eltypes(tuple_type_tail(T)))

immutable Interval{T,closed1,closed2}
    lo::T
    hi::T
end

Interval{T}(lo::T,hi::T) = Interval{T,true,true}(lo,hi)

in{T}(x, i::Interval{T,false,false}) = i.lo <  x <  i.hi
in{T}(x, i::Interval{T,true,false})  = i.lo <= x <  i.hi
in{T}(x, i::Interval{T,false,true})  = i.lo <  x <= i.hi
in{T}(x, i::Interval{T,true,true})   = i.lo <= x <= i.hi

abstract Dimension{T<:Real}

==(a::Dimension, b::Dimension) = a.value == b.value
isless(a::Dimension, b::Dimension) = isless(a.value, b.value)
# these convert definitions are ambiguous unless Dimension's
# parameter is restricted (I picked Real)
convert{T<:Real}(::Type{T}, d::Dimension{T}) = d.value
convert{T<:Dimension}(::Type{T}, x::Real) = T(x)

default{T}(D::Type{Dimension{T}}) = D(default(T))

function show(io::IO, d::Dimension)
    print(io, typeof(d).name, "(")
    show(io, d.value)
    print(io, ")")
end

macro dimension(d)
    T = esc(:T); d = esc(d)
    quote
        immutable ($d){$T <: Real} <: Dimension{$T}
            value::($T)
        end
    end
end

# dimension where all values x are lo <= x <= hi
#abstract BoundedDimension{T, lo, hi} <: Dimension{T}

# maybe: dimension where all values belong to some Range
#abstract RangeDimension{T, r} <: Dimension{T}

# lexicographic order product iterator

import Base: length, eltype, start, next, done

abstract AbstractProdIterator

immutable Prod2{I1, I2} <: AbstractProdIterator
    a::I1
    b::I2
end

product(a) = a
product(a, b) = Prod2(a, b)
eltype{I1,I2}(::Type{Prod2{I1,I2}}) = Tuple{eltype(I1), eltype(I2)}
length(p::AbstractProdIterator) = length(p.a)*length(p.b)

function start(p::AbstractProdIterator)
    s1, s2 = start(p.a), start(p.b)
    s1, s2, (done(p.a,s1) || done(p.b,s2))
end

function prod_next(p, st)
    s1, s2 = st[1], st[2]
    v2, s2 = next(p.b, s2)
    doneflag = false
    if done(p.b, s2)
        v1, s1 = next(p.a, s1)
        if !done(p.a, s1)
            s2 = start(p.b)
        else
            doneflag = true
        end
    else
        v1, _ = next(p.a, s1)
    end
    return (v1,v2), (s1,s2,doneflag)
end

next(p::Prod2, st) = prod_next(p, st)
done(p::AbstractProdIterator, st) = st[3]

immutable Prod{I1, I2<:AbstractProdIterator} <: AbstractProdIterator
    a::I1
    b::I2
end

product(a, b, c...) = Prod(a, product(b, c...))
eltype{I1,I2}(::Type{Prod{I1,I2}}) = tuple_type_cons(eltype(I1), eltype(I2))

function next{I1,I2}(p::Prod{I1,I2}, st)
    x = prod_next(p, st)
    ((x[1][1],x[1][2]...), x[2])
end
