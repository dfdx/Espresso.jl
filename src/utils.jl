
# utils.jl - utility functions


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


# function countdict(a::AbstractArray{T}) where T
#     counts = OrderedDict{T, Int}()
#     for x in a
#         if haskey(counts, x)
#             counts[x] += 1
#         else
#             counts[x] = 1
#         end
#     end
#     return counts
# end


unzip(coll) = map(collect, zip(coll...))



## package-specific stuff

# func_name(f) = Base.function_name(f)
func_name(f) = nameof(f)
# func_mod(f) = Base.function_module(f)
func_mod(f) = Base.parentmodule(typeof(f))


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
function canonical(cur_mod::Module, qname)
    try
        f = Core.eval(cur_mod, qname)
        if f isa Function
            mod = func_mod(f)
            name = func_name(f)
            # TODO: review operators and module names for Julia 0.7/1.0
            if qname in [:.*, :./, :.+, :.-, :.^, :.>, :.<, :.>=, :.<=, :.==]
                return qname  # for Julia 0.6 only
            elseif (mod == cur_mod || mod == Main || mod == Base || mod == Base.Math ||
                    mod == Base.DSP)
                return Symbol(name)
            else
                # there should be a smarter way to do it...
                parts = map(Symbol, split(string(mod), "."))
                mod_ex = dot_expr(parts)
                return Expr(:., mod_ex, QuoteNode(name))
            end
        elseif f isa DataType || f isa UnionAll
            # parts = split(string(f), ".")
            # mod = eval(cur_mod, parse(join(parts[1:end-1], ".")))
            # name = parse(parts[end])
            return parse(string(f))    # use it for functions as well?
        else
            error("Can't understand module of $f")
        end
    catch e
        # if qname isn't defined in module `cur_mod`, return it as is
        if isa(e, UndefVarError)
            return qname
        else
            throw(e)
        end
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
    new_st = empty(st)
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

See also: split_params
"""
function parse_call_args(ex::ExH{:call})
    ordinary_args = []
    kw_args = Dict()
    for arg in ex.args[2:end]
        if arg isa Expr && arg.head == :kw
            kw_args[arg.args[1]] = arg.args[2]
        elseif arg isa Expr && arg.head == :parameters
            for kw in arg.args
                kw_args[kw.args[1]] = kw.args[2]
            end
        else
            push!(ordinary_args, arg)
        end
    end
    return ordinary_args, kw_args
end


function parse_call_args(ex::Expr)
    @assert ex.head == :call
    return parse_call_args(ExH(ex))
end


"""
Parse call expression into function name, ordinary and keyword arguments.
:kw and :parameters arguments are treated the same way.

The reverse of this operation is make_call_expr()
"""
function parse_call_expr(ex::Expr)
    @assert ex.head == :call
    op = ex.args[1]
    ordinary_args, kw_args = parse_call_args(ex)
    return op, ordinary_args, kw_args
end


"""
Make call expression from function name, ordinary and keyword arguments.

The reverse of this operation is parse_call_expr()
"""
function make_call_expr(op::Symbol, args::Vector, kw_args::Dict=Dict{Any,Any}())
    if isempty(kw_args)
        return Expr(:call, op, args...)
    else
        return Expr(:call, op, make_kw_params(kw_args), args...)
    end
end


"""
Split parameters of a function signature, returning a list of (param name, param type) tuples
and a list of keyword parameters.

See also: parse_call_args
"""
function split_params(sig::Expr)
    if length(sig.args) == 1
        return Tuple{Symbol,Symbol}[], Any[]
    elseif isa(sig.args[2], Expr) && sig.args[2].head == :parameters
        kw_params = Any[a.args[1] => a.args[2] for a in sig.args[2].args]
        params = [(arg.args[1], arg.args[2]) for arg in sig.args[3:end]]
        return params, kw_params
    else
        return [(arg.args[1], arg.args[2]) for arg in sig.args[2:end]], []
    end
end


"""
Remove all :kw and :parameters nodes from a call expression
"""
function without_keywords(ex::Expr)
    @assert ex.head == :call
    ex = without(ex, Expr(:parameters, Expr(:..., :_x)))
    ex = without(ex, Expr(:kw, Expr(:..., :_x)))
    return ex
end


function with_keywords(ex::Expr, kw_args::Dict)
    @assert ex.head == :call
    if isempty(kw_args)
        return ex
    else
        return Expr(:call, ex.args[1], make_kw_params(kw_args), ex.args[2:end]...)
    end
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
    new_ex = macroexpand(@__MODULE__, :(@. $ex))
    if isa(new_ex, Expr) && new_ex.head == :.= && lhs_is_scalar
        new_ex.head = :(=)  # can't use :.= if LHS is scalar
    end
    return new_ex
end


## force bitness

force_bitness(x::AbstractFloat, ::Val{32}) = Float32(x)
force_bitness(x::AbstractFloat, ::Val{64}) = Float64(x)

force_bitness(x::AT, ::Val{64}) where {AT <: AbstractArray{T,N}} where {T <: AbstractFloat, N} =
    convert(AbstractArray{Float64, N}, x)
force_bitness(x::AT, ::Val{32}) where {AT <: AbstractArray{T,N}} where {T <: AbstractFloat, N} =
    convert(AbstractArray{Float32, N}, x)

# don't touch integers since they normally don't affect bitness stability
# e.g. try `rand(Float32, 10) * 2`
force_bitness(x::Integer, ::Val{B}) where B = x


## fixes for Julia 0.7

# to_dict(t::NamedTuple) = Dict(zip(keys(t), t))
to_dict(x::Base.Iterators.Pairs) = Dict(x)


## handling of different modules

const KNOWN_MODULES = Set([:Core, :Base, :MainInclude, :REPL, :Espresso, :XGrad])

function get_caller_module()
    s = stacktrace()
    for i=2:length(s)        
        if s[i].linfo isa Core.MethodInstance
            mod = s[i].linfo.def.module
            if !in(nameof(mod), KNOWN_MODULES)
                return mod
            end
        end
    end
    return Main
    # error("Can't get module of a caller from the stacktrace")
end


# EinGraph deprecation

function depwarn_eingraph(funcsym)
    Base.depwarn("Einstein notation is deprecated and will be removed in Espresso 0.4.0",
                 funcsym)
end
