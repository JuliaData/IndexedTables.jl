using Base.Test
import Base: tuple_type_cons, tuple_type_head, tuple_type_tail, in, ==, isless, convert,
             length, eltype, start, next, done, show

export @NT

eltypes(::Type{Tuple{}}) = Tuple{}
eltypes{T<:Tuple}(::Type{T}) =
    tuple_type_cons(eltype(tuple_type_head(T)), eltypes(tuple_type_tail(T)))
eltypes{T<:NamedTuple}(::Type{T}) = map_params(eltype, T)
eltypes(::Type{T}) where T <: Pair = map_params(eltypes, T)
eltypes(::Type{T}) where T<:AbstractArray{S, N} where {S, N} = S
Base.@pure astuple{T<:NamedTuple}(::Type{T}) = Tuple{T.parameters...}
astuple{T<:Tuple}(::Type{T}) = T

# sizehint, making sure to return first argument
_sizehint!(a::Array{T,1}, n::Integer) where {T} = (sizehint!(a, n); a)
_sizehint!(a::AbstractArray, sz::Integer) = a

# argument selectors
left(x, y) = x
right(x, y) = y

# tuple and NamedTuple utilities

@inline ith_all(i, ::Tuple{}) = ()
@inline ith_all(i, as) = (as[1][i], ith_all(i, tail(as))...)

@generated function ith_all(i, n::NamedTuple)
    Expr(:block,
         :(@Base._inline_meta),
         Expr(:tuple, [ Expr(:ref, Expr(:., :n, Expr(:quote, fieldname(n,f))), :i) for f = 1:nfields(n) ]...))
end

@inline foreach(f, a::Tuple) = _foreach(f, a[1], tail(a))
@inline _foreach(f, x, ra) = (f(x); _foreach(f, ra[1], tail(ra)))
@inline _foreach(f, x, ra::Tuple{}) = f(x)

@generated function foreach(f, n::NamedTuple)
    Expr(:block, [ Expr(:call, :f, Expr(:., :n, Expr(:quote, fieldname(n,f)))) for f = 1:nfields(n) ]...)
end

@inline foreach(f, a::Pair) = (f(a.first); f(a.second))
@inline foreach(f, a::Pair, b::Pair) = (f(a.first, b.first); f(a.second, b.second))

@inline foreach(f, a::Tuple, b::Tuple) = _foreach(f, a[1], b[1], tail(a), tail(b))
@inline _foreach(f, x, y, ra, rb) = (f(x, y); _foreach(f, ra[1], rb[1], tail(ra), tail(rb)))
@inline _foreach(f, x, y, ra::Tuple{}, rb) = f(x, y)

@generated function foreach(f, n::Union{Tuple,NamedTuple}, m::Union{Tuple,NamedTuple})
    Expr(:block,
         :(@Base._inline_meta),
         [ Expr(:call, :f,
                Expr(:call, :getfield, :n, f),
                Expr(:call, :getfield, :m, f)) for f = 1:nfields(n) ]...)
end

fieldindex(x, i::Integer) = i
fieldindex(x::NamedTuple, s::Symbol) = findfirst(x->x===s, fieldnames(x))

astuple(t::Tuple) = t

@generated function astuple(n::NamedTuple)
    Expr(:tuple, [ Expr(:., :n, Expr(:quote, fieldname(n,f))) for f = 1:nfields(n) ]...)
end

# lexicographic order product iterator

import Base: length, eltype, start, next, done

abstract type AbstractProdIterator end

struct Prod2{I1, I2} <: AbstractProdIterator
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

struct Prod{I1, I2<:AbstractProdIterator} <: AbstractProdIterator
    a::I1
    b::I2
end

product(a, b, c...) = Prod(a, product(b, c...))
eltype{I1,I2}(::Type{Prod{I1,I2}}) = tuple_type_cons(eltype(I1), eltype(I2))

function next(p::Prod{I1,I2}, st) where {I1,I2}
    x = prod_next(p, st)
    ((x[1][1],x[1][2]...), x[2])
end

# sortperm with counting sort

sortperm_fast(x) = sortperm(x)

function sortperm_fast(v::Vector{T}) where T<:Integer
    n = length(v)
    if n > 1
        min, max = extrema(v)
        rangelen = max - min + 1
        if rangelen < div(n,2)
            return sortperm_int_range(v, rangelen, min)
        end
    end
    return sortperm(v, alg=MergeSort)
end

function sortperm_int_range(x::Vector{T}, rangelen, minval) where T<:Integer
    offs = 1 - minval
    n = length(x)

    where = fill(0, rangelen+1)
    where[1] = 1
    @inbounds for i = 1:n
        where[x[i] + offs + 1] += 1
    end
    cumsum!(where, where)

    P = Vector{Int}(n)
    @inbounds for i = 1:n
        label = x[i] + offs
        wl = where[label]
        P[wl] = i
        where[label] = wl+1
    end

    return P
end

# sort the values in v[i0:i1] in place, by array `by`
function sort_sub_by!(v, i0, i1, by, order, temp)
    empty!(temp)
    sort!(v, i0, i1, MergeSort, order, temp)
end

function sort_sub_by!(v, i0, i1, by::PooledArray, order, temp)
    empty!(temp)
    sort!(v, i0, i1, MergeSort, order, temp)
end

function sort_sub_by!(v, i0, i1, by::Vector{T}, order, temp) where T<:Integer
    min = max = by[v[i0]]
    @inbounds for i = i0+1:i1
        val = by[v[i]]
        if val < min
            min = val
        elseif val > max
            max = val
        end
    end
    rangelen = max-min+1
    n = i1-i0+1
    if rangelen <= n
        sort_int_range_sub_by!(v, i0-1, n, by, rangelen, min, temp)
    else
        empty!(temp)
        sort!(v, i0, i1, MergeSort, order, temp)
    end
    v
end

# in-place counting sort of x[ioffs+1:ioffs+n] by values in `by`
function sort_int_range_sub_by!(x, ioffs, n, by, rangelen, minval, temp)
    offs = 1 - minval

    where = fill(0, rangelen+1)
    where[1] = 1
    @inbounds for i = 1:n
        where[by[x[i+ioffs]] + offs + 1] += 1
    end
    cumsum!(where, where)

    length(temp) < n && resize!(temp, n)
    @inbounds for i = 1:n
        xi = x[i+ioffs]
        label = by[xi] + offs
        wl = where[label]
        temp[wl] = xi
        where[label] = wl+1
    end

    @inbounds for i = 1:n
        x[i+ioffs] = temp[i]
    end
    x
end

function append_n!(X, val, n)
    l = length(X)
    resize!(X, l+n)
    for i in (1:n)+l
        @inbounds X[i] = val
    end
    X
end

const _namedtuple_cache = Dict{Tuple{Vararg{Symbol}}, Type}()
function namedtuple(fields...)
    if haskey(_namedtuple_cache, fields)
        return _namedtuple_cache[fields]
    else
        NT = eval(:(@NT($(fields...))))
        _namedtuple_cache[fields] = NT
        return NT
    end
end

"""
`arrayof(T)`

Returns the type of `Columns` or `Vector` suitable to store
values of type T. Nested tuples beget nested Columns.
"""
Base.@pure function arrayof(S)
    T = strip_unionall(S)
    if T == Union{}
        Vector{Union{}}
    elseif T<:Tuple
        Columns{T, Tuple{map(arrayof, T.parameters)...}}
    elseif T<:NamedTuple
        Columns{T,namedtuple(fieldnames(T)...){map(arrayof, T.parameters)...}}
    elseif T<:DataValue
        DataValueArray{T.parameters[1],1}
    elseif T<:Pair
        Columns{T, Pair{map(arrayof, T.parameters)...}}
    else
        Vector{T}
    end
end

@inline strip_unionall_params(T::UnionAll) = strip_unionall_params(T.body)
@inline strip_unionall_params(T) = map(strip_unionall, T.parameters)

Base.@pure function promote_union(T::Type)
    if isa(T, Union)
        return promote_type(T.a, promote_union(T.b))
    else
        return T
    end
end

Base.@pure function strip_unionall(T)
    if isleaftype(T) || T == Union{}
        return T
    elseif isa(T, TypeVar)
        T.lb === Union{} && return strip_unionall(T.ub)
        return Any
    elseif T == Tuple
        return Any
    elseif T<:Tuple
        if any(x->x <: Vararg, T.parameters)
            # we only keep known-length tuples
            return Any
        else
            return Tuple{strip_unionall_params(T)...}
        end
    elseif T<:NamedTuple
        if isa(T, Union)
            return promote_union(T)
        else
            NT = namedtuple(fieldnames(T)...)
            return NT{strip_unionall_params(T)...}
        end
    elseif isa(T, UnionAll)
        return Any
    elseif isa(T, Union)
        return promote_union(T)
    elseif T.abstract
        return T
    else
        return Any
    end
end

Base.@pure function _promote_op{S}(f, ::Type{S})
    t = Core.Inference.return_type(f, Tuple{Base._default_type(S)})
    strip_unionall(t)
end

Base.@pure function _promote_op{S,T}(f, ::Type{S}, ::Type{T})
    t = Core.Inference.return_type(f, Tuple{Base._default_type(S),
                                        Base._default_type(T)})
    strip_unionall(t)
end

_map(f, p::Pair) = f(p.first) => f(p.second)
_map(f, args...) = map(f, args...)

# The following is not inferable, this is OK because the only place we use
# this doesn't need it.

function _map_params(f, T, S)
    (f(_tuple_type_head(T), _tuple_type_head(S)), _map_params(f, _tuple_type_tail(T), _tuple_type_tail(S))...)
end

_map_params(f, T::Type{Tuple{}},S::Type{Tuple{}}) = ()

map_params(f, ::Type{T}, ::Type{S}) where {T,S} = f(T,S)
map_params(f, ::Type{T}) where {T} = map_params((x,y)->f(x), T, T)
map_params(f, ::Type{T}) where T <: Pair{S1, S2} where {S1, S2} = Pair{f(S1), f(S2)}
@inline _tuple_type_head{T<:Tuple}(::Type{T}) = Base.tuple_type_head(T)
@inline _tuple_type_tail{T<:Tuple}(::Type{T}) = Base.tuple_type_tail(T)

#function map_params{N}(f, T::Type{T} where T<:Tuple{Vararg{Any,N}}, S::Type{S} where S<: Tuple{Vararg{Any,N}})
Base.@pure function map_params{T<:Tuple,S<:Tuple}(f, ::Type{T}, ::Type{S})
    if nfields(T) != nfields(S)
        MethodError(map_params, (typeof(f), T,S))
    end
    Tuple{_map_params(f, T,S)...}
end

_tuple_type_head(T::Type{NT}) where {NT<: NamedTuple} = fieldtype(NT, 1)

Base.@pure function _tuple_type_tail{NT<: NamedTuple}(T::Type{NT})
    Tuple{Base.argtail(NT.parameters...)...}
end

Base.@pure @generated function map_params{T<:NamedTuple,S<:NamedTuple}(f, ::Type{T}, ::Type{S})
    if fieldnames(T) != fieldnames(S)
        MethodError(map_params, (T,S))
    end
    NT = Expr(:macrocall, :(NamedTuples.$(Symbol("@NT"))), fieldnames(T)...)
    :($NT{_map_params(f, T, S)...})
end

@inline function concat_tup(a::NamedTuple, b::NamedTuple)
    concat_tup_type(typeof(a), typeof(b))(a..., b...)
end
@inline concat_tup(a::Tup, b::Tup) = (a..., b...)
@inline concat_tup(a::Tup, b) = (a..., b)
@inline concat_tup(a, b::Tup) = (a, b...)
@inline concat_tup(a, b) = (a..., b...)

Base.@pure function concat_tup_type(T::Type{<:Tuple}, S::Type{<:Tuple})
    Tuple{T.parameters..., S.parameters...}
end

Base.@pure function concat_tup_type{
           T<:NamedTuple,S<:NamedTuple}(::Type{T}, ::Type{S})
    namedtuple(fieldnames(T)..., fieldnames(S)...){T.parameters..., S.parameters...}
end

Base.@pure function concat_tup_type(T::Type, S::Type)
    Tuple{T,S}
end

# check to see if array has shared data
# used in flush! to create a copy of the arrays
function isshared(x)
    try
        resize!(x, length(x))
        false
    catch err
        if err isa ErrorException && err.msg == "cannot resize array with shared data"
            return true
        else
            rethrow(err)
        end
    end
end
