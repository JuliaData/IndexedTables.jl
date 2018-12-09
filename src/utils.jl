(T::Type{<:StringArray})(::typeof(undef), args...) = T(args...)

fastmap(f, xs...) = map(f, xs...)
@generated function fastmap(f, xs::NTuple{N}...) where N
    args = [:(xs[$j][i])  for j in 1:fieldcount(typeof(xs))]
    :(Base.@ntuple $N i -> f($(args...)))
end

eltypes(::Type{Tuple{}}) = Tuple{}
eltypes(::Type{T}) where {T<:Tuple} =
    tuple_type_cons(eltype(tuple_type_head(T)), eltypes(tuple_type_tail(T)))
eltypes(::Type{T}) where {T<:NamedTuple} = map_params(eltype, T)
eltypes(::Type{T}) where T <: Pair = map_params(eltypes, T)
eltypes(::Type{T}) where T<:AbstractArray{S, N} where {S, N} = S
astuple(::Type{T}) where {T<:NamedTuple} = fieldstupletype(T)
astuple(::Type{T}) where {T<:Tuple} = T

# sizehint, making sure to return first argument
_sizehint!(a::Array{T,1}, n::Integer) where {T} = (sizehint!(a, n); a)
_sizehint!(a::AbstractArray, sz::Integer) = a

# argument selectors
left(x, y) = x
right(x, y) = y

# tuple and NamedTuple utilities

ith_all(i::Integer, xs::Union{Tuple, NamedTuple}) = map(x -> x[i], xs)

@generated function foreach(f, x::Union{NamedTuple, Tuple}, xs::Union{NamedTuple, Tuple}...)
    args = [:(getfield(getfield(xs, $j), i))  for j in 1:length(xs)]
    :(Base.@nexprs $(fieldcount(x)) i -> f(getfield(x, i), $(args...)); nothing)
end

@inline foreach(f, a::Pair) = (f(a.first); f(a.second))
@inline foreach(f, a::Pair, b::Pair) = (f(a.first, b.first); f(a.second, b.second))

fieldindex(x, i::Integer) = i
fieldindex(x::NamedTuple, s::Symbol) = findfirst(x->x===s, fieldnames(typeof(x)))

astuple(t::Tuple) = t

astuple(n::NamedTuple) = Tuple(n)

# sortperm with counting sort

sortperm_fast(x) = sortperm(x)
sortperm_fast(x::StringVector) = sortperm(convert(StringVector{WeakRefString{UInt8}}, x))

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

    P = Vector{Int}(undef, n)
    @inbounds for i = 1:n
        label = x[i] + offs
        wl = where[label]
        P[wl] = i
        where[label] = wl+1
    end

    return P
end

# sort the values in v[i0:i1] in place, by array `by`
Base.@noinline function sort_sub_by!(v, i0, i1, by, order, temp)
    empty!(temp)
    sort!(v, i0, i1, MergeSort, order, temp)
end

Base.@noinline function sort_sub_by!(v, i0, i1, by::PooledArray, order, temp)
    empty!(temp)
    sort!(v, i0, i1, MergeSort, order, temp)
end

Base.@noinline function sort_sub_by!(v, i0, i1, by::Vector{T}, order, temp) where T<:Integer
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
    for i in (1:n) .+ l
        @inbounds X[i] = val
    end
    X
end

fieldstupletype(::Type{NamedTuple{N,T}}) where {N,T} = T
fieldstupletype(T::Type{<:Tuple}) = T

fieldtypes(x::Type) = fieldstupletype(x).parameters

function namedtuple(fields...)
    NamedTuple{fields}
end

"""
    arrayof(T)

Returns the type of `Columns` or `Vector` suitable to store
values of type T. Nested tuples beget nested Columns.
"""
Base.@pure function arrayof(S)
    T = strip_unionall(S)
    if T == Union{}
        Vector{Union{}}
    elseif T<:Tuple
        Columns{T, Tuple{map(arrayof, fieldtypes(T))...}}
    elseif T<:NamedTuple
        if fieldcount(T) == 0
            Columns{NamedTuple{(), Tuple{}}, NamedTuple{(), Tuple{}}}
        else
            Columns{T,NamedTuple{fieldnames(T), Tuple{map(arrayof, fieldtypes(T))...}}}
        end
    elseif (T<:Union{Missing,String,WeakRefString} && Missing<:T) ||
        T<:Union{String, WeakRefString}
        StringArray{T, 1}
    elseif T<:Pair
        Columns{T, Pair{map(arrayof, T.parameters)...}}
    else
        Vector{T}
    end
end

@inline strip_unionall_params(T::UnionAll) = strip_unionall_params(T.body)
@inline strip_unionall_params(T) = map(strip_unionall, fieldtypes(T))

Base.@pure function promote_union(T::Type)
    if isa(T, Union)
        return promote_type(T.a, promote_union(T.b))
    else
        return T
    end
end

Base.@pure function strip_unionall(T)
    if isconcretetype(T) || T == Union{}
        return T
    elseif isa(T, TypeVar)
        T.lb === Union{} && return strip_unionall(T.ub)
        return Any
    elseif T == Tuple
        return Any
    elseif T<:Tuple
        if any(x->x <: Vararg, fieldtypes(T))
            # we only keep known-length tuples
            return Any
        else
            return Tuple{strip_unionall_params(T)...}
        end
    elseif T<:NamedTuple
        if isa(T, Union)
            return promote_union(T)
        else
            return NamedTuple{fieldnames(T),
                              Tuple{strip_unionall_params(T)...}}
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

Base.@pure function _promote_op(f, ::Type{S}) where S
    t = Core.Compiler.return_type(f, Tuple{S})
    strip_unionall(t)
end

Base.@pure function _promote_op(f, ::Type{S}, ::Type{T}) where {S,T}
    t = Core.Compiler.return_type(f, Tuple{S, T})
    strip_unionall(t)
end

@inline _map(f, p::Pair) = f(p.first) => f(p.second)
@inline _map(f, args...) = map(f, args...)

# The following is not inferable, this is OK because the only place we use
# this doesn't need it.

function _map_params(f, T, S)
    (f(_tuple_type_head(T), _tuple_type_head(S)),
     _map_params(f, _tuple_type_tail(T), _tuple_type_tail(S))...)
end

_map_params(f, T::Type{Tuple{}},S::Type{Tuple{}}) = ()

map_params(f, ::Type{T}, ::Type{S}) where {T,S} = f(T,S)
map_params(f, ::Type{T}) where {T} = map_params((x,y)->f(x), T, T)
map_params(f, ::Type{T}) where T <: Pair{S1, S2} where {S1, S2} = Pair{f(S1), f(S2)}
@inline _tuple_type_head(::Type{T}) where {T<:Tuple} = Base.tuple_type_head(T)
@inline _tuple_type_tail(::Type{T}) where {T<:Tuple} = Base.tuple_type_tail(T)

#function map_params{N}(f, T::Type{T} where T<:Tuple{Vararg{Any,N}}, S::Type{S} where S<: Tuple{Vararg{Any,N}})
Base.@pure function map_params(f, ::Type{T}, ::Type{S}) where {T<:Tuple,S<:Tuple}
    if fieldcount(T) != fieldcount(S)
        MethodError(map_params, (typeof(f), T,S))
    end
    Tuple{_map_params(f, T,S)...}
end

_tuple_type_head(T::Type{NT}) where {NT<: NamedTuple} = fieldtype(NT, 1)

Base.@pure function _tuple_type_tail(T::Type{NT}) where NT<: NamedTuple
    Tuple{Base.argtail(fieldtypes(NT)...)...}
end

Base.@pure function map_params(f, ::Type{T}, ::Type{S}) where {T<:NamedTuple,S<:NamedTuple}
    if fieldnames(T) != fieldnames(S)
        MethodError(map_params, (T,S))
    end
    if fieldcount(T) == 0 && fieldcount(S) == 0
        return T
    end

    NamedTuple{fieldnames(T),
               map_params(f,
                          fieldstupletype(T),
                          fieldstupletype(S))}
end

@inline function concat_tup(a::NamedTuple, b::NamedTuple)
    concat_tup_type(typeof(a), typeof(b))((a..., b...))
end
@inline concat_tup(a::Tup, b::Tup) = (a..., b...)
@inline concat_tup(a::Tup, b) = (a..., b)
@inline concat_tup(a, b::Tup) = (a, b...)
@inline concat_tup(a, b) = (a..., b...)

Base.@pure function concat_tup_type(T::Type{<:Tuple}, S::Type{<:Tuple})
    Tuple{fieldtypes(T)..., fieldtypes(S)...}
end

Base.@pure function concat_tup_type(::Type{T}, ::Type{S}) where {
           T<:NamedTuple,S<:NamedTuple}
    fieldcount(T) == 0 && fieldcount(S) == 0 ?
        namedtuple() :
        namedtuple(fieldnames(T)...,
                   fieldnames(S)...){Tuple{fieldtypes(T)...,
                                           fieldtypes(S)...}}
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

compact_mem(x) = x
compact_mem(x::StringArray{String}) = convert(StringArray{WeakRefString{UInt8}}, x)

function getsubfields(n::NamedTuple, fields)
    fns = fieldnames(typeof(n))
    NamedTuple{(fns[fields]...,)}(n)
end
getsubfields(t::Tuple, fields) = t[fields]

# lexicographic order product iterator

product(itr) = itr
product(itrs...) = Base.Generator(reverse, Iterators.product(reverse(itrs)...))
