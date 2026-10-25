# Upgrade models saved under an older BLPDemand/BLP layout (JLD2 returns
# ReconstructedMutable for them) to the current structs in blp.jl.
# Usage: julia upgrade_models.jl [models_dir]   (default: models)
using JLD2, LinearAlgebra
include("blp.jl")

# Copy every field the current struct has from `old`; the rest fall back to defaults
function upgrade(old, ::Type{T}; kwargs...) where T
    fields = Dict{Symbol,Any}()
    for f in fieldnames(T)
        hasproperty(old, f) && (fields[f] = getproperty(old, f))
    end
    merge!(fields, Dict(kwargs))
    return T(; fields...)
end

function upgrade_demand(old)
    d = upgrade(old, blp.BLPDemand)
    # Fields added after the old layout: rebuild from saved ones
    if !hasproperty(old, :ps_sim)
        d.ps_sim = sum(reshape(d.profit_sim, (d.J, d.T)), dims = 1)'
        d.ts_sim = d.cs_sim + d.ps_sim
    end
    return d
end

# JLD2 calls this for every stale BLPDemand it meets, including ones nested in a BLP
Base.convert(::Type{blp.BLPDemand}, nt::NamedTuple) = upgrade_demand(nt)
typemap = Dict("Main.blp.BLPDemand" => JLD2.Upgrade(blp.BLPDemand))

dir = length(ARGS) >= 1 ? ARGS[1] : "models"
for path in filter(f -> endswith(f, ".jdl2"), readdir(dir; join = true))
    if isfile(path * ".bak")   # already upgraded on a previous run
        println("skipped (has .bak): ", path)
        continue
    end
    new = jldopen(f -> f["model"], path, "r"; typemap = typemap)
    cp(path, path * ".bak")
    JLD2.jldsave(path; model = new)
    println("upgraded: ", path, " -> ", typeof(new))
end
