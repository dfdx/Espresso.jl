
if !isdefined(:__EXPRESSION_HASHES__)
    __EXPRESSION_HASHES__ = Set{UInt64}()
end

macro runonce(expr)
    h = hash(expr)
    return esc(quote
        if !in($h, __EXPRESSION_HASHES__)
            push!(__EXPRESSION_HASHES__, $h)
            $expr
        end
    end)
end


function flatten!(b::Vector, a::Vector)
    for x in a
        if isa(x, Array)
            flatten!(b, x)
        else
            push!(b, x)
        end
    end
    return b
end

flatten(a::Vector) = flatten!(eltype(a)[], a)
flatten{T}(::Type{T}, a::Vector) = convert(Vector{T}, flatten(a))


## package-specific stuff

if VERSION < v"0.5"
    func_name(f) = f.env.name
    func_mod(f) = f.env.module
else
    func_name(f) = Base.function_name(f)
    func_mod(f) = Base.function_module(f)
end


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
    Mod.foo ==> Mod.foo
"""
function canonical(qname)
    f = eval(qname)
    mod = func_mod(f)
    name = func_name(f)
    if mod == Base || mod == Base.Math # what else should we add?
        return Symbol(name)
    else
        # there should be a smarter way to do it...
        parts = map(Symbol, split(string(mod), "."))
        mod_ex = dot_expr(parts)
        return Expr(:., mod_ex, QuoteNode(name))
    end
end
