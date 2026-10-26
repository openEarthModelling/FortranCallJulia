# Runs inside the library build (precompile_execution_file): everything
# compiled here is baked into libkinetics.so, so the @ccallable wrappers
# and the FjKinetics hot path never compile on the deployed machine.

using KineticsAOT

nspec = KineticsAOT.kinetics_build(164180.0, 25.0, 1.0, 25.0, 2.5)
nspec == 2 || error("aot precompile: bad mechanism")

# exercise kinetics_step's unsafe_wrap path directly with Julia pointers
# (identical method body to the ccall'd entry)
y = zeros(8, 2); y[:, 1] .= 1.0
t = fill(17.0, 8)
rho = fill(1.0, 8)
rc = KineticsAOT.kinetics_step(pointer(y), pointer(t), pointer(rho),
                                Int32(8), 4.0e-4)
rc == 0 || error("aot precompile: step failed")

# the view/active-set slicing shape used by the bridge driver
# (FjKinetics is visible through KineticsAOT's own `using`)
KineticsAOT.FjKinetics.step_chemistry!(KineticsAOT.KS[], view(y, 1:4, :),
                                       view(t, 1:4), view(rho, 1:4), 4.0e-4)

println("KineticsAOT precompilation complete.")
