
# type for generating vectorized code
struct VectorCodeGen
end


function generate_code(::VectorCodeGen, g::ExGraph)
    ex = to_expr(g)
    return ex
end


function generate_code(::VectorCodeGen, g::EinGraph)
    ex = from_einstein(g)
    return ex
end
