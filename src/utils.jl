
# utils.jl - utility functions

# @static if VERSION < v"0.7-"
#     println("if")
#     if isdefined(:__EXPRESSION_HASHES__)
#         __EXPRESSION_HASHES__ = Set{AbstractString}()
#     end
# else
#     println("else")
#     if @isdefined __EXPRESSION_HASHES__
#         __EXPRESSION_HASHES__ = Set{AbstractString}()
#     end
# end

# """
# If loaded twice without changes, evaluate expression only for the first time.
# This is useful for reloading code in REPL. For example, the following code will
# produce `invalid redifinition` error if loaded twice:

#     type Point{T}
#         x::T
#         y::T
#     end

# Wrapped into @runonce, however, the code is reloaded fine:

#     @runonce type Point{T}
#         x::T
#         y::T
#     end

# @runonce doesn't have any affect on expression itself.
# """
# macro runonce(expr)
#     h = string(expr)
#     return esc(quote
#         if !in($h, __EXPRESSION_HASHES__)
#             push!(__EXPRESSION_HASHES__, $h)
#             $expr
#         end
#     end)
# end


"""Same as `get` function, but evaluates default_expr only if needed"""
macro get(dict, key, default_expr)
    return esc(quote
        if haskey($dict, $key)
            $dict[$key]
        else
            $default_expr
        end
    end)
end


"""
Same as `@get`, but creates new object from `default_expr` if
it didn't exist before
"""
macro get_or_create(dict, key, default_expr)
    return esc(quote
        if !haskey($dict, $key)
            $dict[$key] = $default_expr
        end
        $dict[$key]
    end)
end



"""
Same as `@get`, but immediately exits function and return `default_expr`
if key doesn't exist.
"""
macro get_or_return(dict, key, default_expr)
    return esc(quote
        if haskey($dict, $key)
            $dict[$key]
        else
            return $default_expr
            nothing  # not reachable, but without it code won't compile
        end
    end)
end

"""
Get array of size `sz` from a `dict` by `key`. If element doesn't exist or
its size is not equal to `sz`, create and return new array
using `default_expr`. If element exists, but is not an error,
throw ArgumentError.
"""
macro get_array(dict, key, sz, default_expr)
    return esc(quote
        if (haskey($dict, $key) && !isa($dict[$key], Array))
            local k = $key
            throw(ArgumentError("Key `$k` exists, but is not an array"))
        end
        if (!haskey($dict, $key) || size($dict[$key]) != $sz)
            # ensure $default_expr results in an ordinary array
            $dict[$key] = convert(Array, $default_expr)
        end
        $dict[$key]
    end)
end



"""Flatten vector of vectors in-place"""
function flatten!(b::Vector, a::Vector)
    for x in a
        if isa(x, AbstractArray)
            flatten!(b, x)
        else
            push!(b, x)
        end
    end
    return b
end

"""Flattenx vector of vectors"""
flatten(a::Vector) = flatten!([], a)
flatten(::Type{T}, a::Vector) where {T} = convert(Vector{T}, flatten(a))

"""Flatten one level of nested vectors"""
function flatten1(a::Vector{Vector{T}}) where T
    result = Array(T, 0)
    for xs in a
        for x in xs
            push!(result, x)
        end
    end
    return result
end


function countdict(a::AbstractArray{T}) where T
    counts = OrderedDict{T, Int}()
    for x in a
        if haskey(counts, x)
            counts[x] += 1
        else
            counts[x] = 1
        end
    end
    return counts
end


unzip(coll) = map(collect, zip(coll...))


"""
Compose functins, similar to Haskell's dot operator:

    @c f g x   # ==> f(g(x))

Note that with current implementation a built-in |> operator may be used instead:

    x |> g |> f

@c may become more powerful than that, though.
"""
macro c(args...)
    ex = args[end]
    for arg in reverse(args[1:end-1])
        ex = Expr(:call, arg, ex)
    end
    return ex
end


## package-specific stuff

func_name(f) = Base.function_name(f)
# func_mod(f) = Base.function_module(f)
func_mod(f) = Base.datatype_module(typeof(f))


"""
Given a list of symbols such as `[:x, :y, :z]` constructs expression `x.y.z`.
This is useful for building expressions of qualified names such as
`Base.LinAlg.exp`.
"""
function dot_expr(args::Vector{Symbol})
    @assert length(args) >= 1
    if length(args) == 1
        return args[1]
    else
        ex = Expr(:., args[1], QuoteNode(args[2]))
        for i=3:length(args)
            ex = Expr(:., ex, QuoteNode(args[i]))
        end
        return ex
    end
end


"""
Return canonical representation of a function name, e.g.:

    Base.+  ==> +
    Main.+  ==> + (resolved to Base.+)
    Base.LinAlg.exp ==> exp
    Mod.foo ==> Mod.foo
"""
function canonical(mod::Module, qname)
    f = eval(mod, qname)
    mod = func_mod(f)
    name = func_name(f)
    if qname in [:.*, :./, :.+, :.-, :.^]
        return qname  # for Julia 0.6 only
    elseif (mod == Main || mod == Base || mod == Base.Math ||
            mod == Base.LinAlg || mod == Base.DSP)
        return Symbol(name)
    else
        # there should be a smarter way to do it...
        parts = map(Symbol, split(string(mod), "."))
        mod_ex = dot_expr(parts)
        return Expr(:., mod_ex, QuoteNode(name))
    end
end

function canonical_calls(mod::Module, ex::Expr)
    if ex.head == :call
        new_args = [canonical_calls(mod, arg) for arg in ex.args[2:end]]
        return Expr(:call, canonical(mod, ex.args[1]), new_args...)
    elseif ex.head == :.
        new_args = [canonical_calls(mod, arg) for arg in ex.args[2:end]]
        return Expr(:., canonical(mod, ex.args[1]), new_args...)
    else
        new_args = [canonical_calls(mod, arg) for arg in ex.args]
        return Expr(ex.head, new_args...)
    end
end

canonical_calls(mod::Module, x) = x


# context

function to_context(d::Union{Dict{K,V},Vector{Pair{K,V}}}) where {K,V}
    ctx = Dict{Any,Any}()
    for (k, v) in d
        ctx[k] = to_context(v)
    end
    return ctx
end

to_context(d::Dict{Any,Any}) = d
to_context(x) = x

# guards

"""create cross-reference dict of cliques"""
function cliqueset(pairs::Vector{Tuple{T,T}}) where T
    cliques = Dict{T, Set{T}}()
    for (x1, x2) in pairs
        has_x1 = haskey(cliques, x1)
        has_x2 = haskey(cliques, x2)
        if !has_x1 && !has_x2
            set = Set([x1, x2])
            cliques[x1] = set
            cliques[x2] = set
        elseif has_x1 && !has_x2
            push!(cliques[x1], x2)
            cliques[x2] = cliques[x1]
        elseif !has_x1 && has_x2
            push!(cliques[x2], x1)
            cliques[x1] = cliques[x2]
        end
    end
    return cliques
end


function crosspairs(pairs::Vector{Tuple{T,T}}) where T
    cliques = cliqueset(pairs)
    xpairs = Set{Tuple{T,T}}()
    for (x, ys) in cliques
        for y in ys
            if x != y
                mn, mx = min(x, y), max(x, y)
                push!(xpairs, (mn, mx))
            end
        end
    end
    return xpairs
end


function reduce_equalities(pairs::Vector{Tuple{T,T}}, anchors::Set{T}; replace_anchors=true) where T
    # Q: Why do we need prop_subs here?
    # cliques = cliqueset([(k, v) for (k, v) in prop_subs(Dict(pairs))])
    cliques = cliqueset(pairs)
    st = Dict{T,T}()
    new_pairs = Set{Tuple{T,T}}()
    for (x, ys) in cliques
        for y in ys
            if x == y
                continue
            elseif in(x, anchors) && in(y, anchors)
                # replace larger anchor with smaller one, keep pair
                mn, mx = min(x, y), max(x, y)
                if replace_anchors
                    st[mx] = mn
                end
                push!(new_pairs, (mn, mx))
            elseif in(x, anchors)
                # replace non-anchor with anchor
                st[y] = x
            elseif !in(x, anchors) && !in(y, anchors)
                # replace larger element with smaller one
                mn, mx = min(x, y), max(x, y)
                st[mx] = mn
            end
        end
    end
    return st, collect(new_pairs)
end


"""
Reduce a list of guards. Optional parameters:

 * keep : iterable, indices that need to be kept; default = []
 * used : iterable, indices used in indexed expression; default = all indices

"""
function reduce_guards(guards::Vector{Expr}; keep=[], used=nothing)
    keep = Set{Any}(keep)
    pairs = [(g.args[2], g.args[3]) for g in guards]
    xpairs = crosspairs(pairs)
    used = used == nothing ? Set(flatten(map(collect, pairs))) : Set{Any}(used)
    ordered = [(min(x, y), max(x, y)) for (x, y) in xpairs if in(x, used) && in(y, used)]
    st = Dict{Any,Any}()
    new_pairs = Tuple{Any,Any}[]
    for (x, y) in ordered
        if in(x, keep) && in(y, keep)
            # requested to keep both indices, don't replace anything
            push!(new_pairs, (x, y))
        elseif in(x, keep)
            # replace 2nd element with the 1st one
            st[y] = x
        elseif in(y, keep)
            # replace 1st element with the 2nd one
            st[x] = y
        else
            # free to replace either way, but keep min index for simplicity
            st[y] = x
        end
    end
    new_guards = [:($x == $y) for (x, y) in new_pairs]
    return prop_subs(st), new_guards
end



function expr_like(x)
    flds = Set(fieldnames(typeof(x)))
    return in(:head, flds) && in(:args, flds)
end


function to_block(exs...)
    new_exs = flatten([expr_like(ex) && ex.head == :block ? ex.args : [ex] for ex in exs])
    return sanitize(Expr(:block, new_exs...))
end


"""
Propagate substitution rules. Example:

    Dict(
        :x => y,
        :y => z
    )

is transformed into:

    Dict(
        :x => z,
        :y => z
    )

"""
function prop_subs(st::Dict)
    new_st = similar(st)
    for (k, v) in st
        while haskey(st, v)
            v = st[v]
        end
        new_st[k] = v
    end
    return new_st
end


function with_guards(ex, guards::Vector{Expr})
    if isempty(guards)
        return ex
    elseif length(guards) == 1
        return :($ex * $(guards[1]))
    else
        return Expr(:call, :*, ex, guards...)
    end
end



function apply_guards(ex::Expr, guards::Vector{Expr}; keep=[])
    return apply_guards(ExH(ex), guards; keep=keep)
end


function apply_guards(ex::ExH{:block}, guards::Vector{Expr}; keep=[])
    res = Expr(:block)
    for subex in ex.args
        new_subex = apply_guards(subex, guards::Vector{Expr}; keep=[])
        push!(res.args, new_subex)
    end
    return res
end


function apply_guards(ex::ExH{:(=)}, guards::Vector{Expr}; keep=[])
    ex = Expr(ex)
    lhs, rhs = ex.args
    used = flatten(get_indices(ex; rec=true))
    keep = vcat(keep, flatten(get_indices(lhs)))
    st, new_guards = reduce_guards(guards; keep=keep, used=used)
    new_lhs = subs(lhs, st)
    new_rhs = with_guards(subs(rhs, st), new_guards)
    return :($new_lhs = $new_rhs)
end


function apply_guards(ex::ExH, guards::Vector{Expr}; keep=[])
    ex = Expr(ex)
    used = flatten(get_indices(ex; rec=true))
    st, new_guards = reduce_guards(guards; keep=keep, used=used)
    new_ex = with_guards(subs(ex, st), new_guards)
    return new_ex
end


apply_guards(x, guards::Vector{Expr}; keep=[]) = x
             

# dot-operators & broadcasting

const DOT_OPS = Set([:.*, :.+, :./, :.-, :.^])
const SIMPLE_TO_DOT = Dict(:* => :.*, :+ => :.+,
                           :/ => :./, :- => :.-,
                           :^ => :.^)

function subs_bcast_with_dot(ex::Expr)
    if ex.head == :. && ex.args[1] in DOT_OPS
        new_args = [subs_bcast_with_dot(arg) for arg in ex.args[2].args]
        return Expr(:call, ex.args[1], new_args...)
    elseif ex.head == :. && ex.args[1] in keys(SIMPLE_TO_DOT)
        new_args = [subs_bcast_with_dot(arg) for arg in ex.args[2].args]
        return Expr(:call, SIMPLE_TO_DOT[ex.args[1]], new_args...)
    else
        new_args = [subs_bcast_with_dot(arg) for arg in ex.args]
        return Expr(ex.head, new_args...)
    end
end

subs_bcast_with_dot(x) = x


## is broadcastable

"""
Check if all operations in this expression are broadcasting
"""
is_bcast(ex::Expr) = is_bcast(ExH(ex))

function is_bcast(ex::ExH{:.})
    bcast = isa(ex.args[2], Expr) && ex.args[2].head == :tuple
    return bcast && all(map(is_bcast, ex.args))
end

function is_bcast(ex::ExH{:call})
    bcast_old = ex.args[1] in DOT_OPS
    return bcast_old && all(map(is_bcast, ex.args))
end

is_bcast(ex::Symbol) = true
is_bcast(ex::Number) = false
is_bcast(x) = error("Don't know if $x is a broadcast expression")

# also see broadcasting for EinGraph nodes in optimize.jl


## function parsing

"""
Given a call expression, parse regular and keyword arguments
"""
function parse_call_args(ex::ExH{:call})
    if length(ex.args) == 1
        return [], Dict()
    elseif isa(ex.args[2], Expr) && ex.args[2].head == :parameters
        kw_args = Dict{Any,Any}(a.args[1] => a.args[2] for a in ex.args[2].args)
        return ex.args[3:end], kw_args
    else
        return ex.args[2:end], Dict()
    end
end


function parse_call_args(ex::Expr)
    @assert ex.head == :call
    return parse_call_args(ExH(ex))
end


## function generation

function make_kw_params(kw_args)
    kw_params = [Expr(:kw, arg...) for arg in kw_args]
    return Expr(:parameters, kw_params...)
end


function make_func_expr(name, args, kw_args, body)
    ex = :(function name() end) |> sanitize
    # set name
    ex.args[1].args[1] = name
    # set kw arguments
    if !isempty(kw_args)
        push!(ex.args[1].args, make_kw_params(kw_args))
    end
    # set arguments
    push!(ex.args[1].args, args...)
    if isa(body, Expr) && body.head == :block
        push!(ex.args[2].args, body.args...)
    else
        push!(ex.args[2].args, body)
    end
    return ex
end


# haskeyexact

# function haskeyexact(d::Dict, key)
#     for (k, v) in d
#         if k == key && typeof(k) == typeof(key)
#             return true
#         end
#     end
#     return false
# end
 


function make_elementwise(ex; lhs_is_scalar=false)
    new_ex = macroexpand(:(@. $ex))
    if isa(new_ex, Expr) && new_ex.head == :.= && lhs_is_scalar
        new_ex.head = :(=)  # can't use :.= if LHS is scalar
    end
    return new_ex
end



# EinGraph deprecation

function depwarn_eingraph(funcsym)
    Base.depwarn("Einstein notation is deprecated and will be removed in Espresso 0.4.0",
                 funcsym)
end

