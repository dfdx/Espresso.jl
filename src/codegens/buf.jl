
struct BufCodeGen
end

@deprecate BufCodeGen(x) BufCodeGen()

#buffer_expr(var, buffer_var, sz_ex) =
#    :($var = @get_or_create $buffer_var $(Expr(:quote, var)) $sz_ex)

const BUF_FT = Float64

function buffer_expr(var, buffer_var, sz)
    if isempty(sz)
        return :($var = $BUF_FT(0.0))
    else
        return  :($var = @get_or_create($buffer_var, $(Expr(:quote, var)),
                                        Array(zeros($BUF_FT, $sz))))
    end
end


function generate_code(codegen::BufCodeGen, g::EinGraph)
    g = eliminate_common(g)    
    ex = to_buffered(g)
    # init_exs = [buffer_expr(var, buffer_var, sz_ex) for (var, sz_ex) in g.ctx[:buff_exprs]
    #             if haskey(g, var) && getcategory(g[var]) != :input]
    init_exs = [buffer_expr(var, :mem, sz) for (var, sz) in g.ctx[:rsizes]
                if haskey(g, var) && getcategory(g[var]) != :input]
    res = Expr(:block, init_exs..., ex.args...)
    return res
end


function generate_code(codegen::BufCodeGen, g::ExGraph)
    g = eliminate_common(g)
    ex = to_buffered(g)
    init_exs = [buffer_expr(var, :mem, sz) for (var, sz) in g.ctx[:rsizes]
                if haskey(g, var) && getcategory(g[var]) != :input]
    res = Expr(:block, init_exs..., ex.args...)
    return res
end
