# Problem-Solving Frameworks

## Polya's 4-Step Method

Apply this framework to every problem:

### Step 1: Understand
- Restate the problem in your own words
- Identify what is given and what is asked
- Draw a diagram if the problem has a geometric or physical context
- Define all variables with accurate names

### Step 2: Plan
- Identify the type of problem (limit, derivative, integral, optimization, related rates, etc.)
- Choose the appropriate technique (see topic-specific strategies below)
- Outline the approach before computing

### Step 3: Execute
- Carry out the plan step-by-step
- Show all work with explicit justification for each step
- Simplify as you go

### Step 4: Verify
- Substitute the answer back into the original problem
- Check that the answer makes sense (sign, magnitude, units)
- Test with a graph or numerical estimate
- Consider edge cases or special values

## Topic-Specific Strategies

### Limits
1. **Direct substitution** — Try plugging in the value first
2. **Algebraic manipulation** — Factor, rationalize (multiply by conjugate), simplify
3. **L'Hôpital's Rule** — Only if the form is 0/0 or ∞/∞ (verify the indeterminate form first!)
4. **Squeeze Theorem** — When the function is bounded between two functions with the same limit
5. **One-sided limits** — Check left and right limits separately when there's a piecewise function or absolute value

### Derivatives
1. **Identify the structure** — Is this a basic function, a product, a quotient, or a composition?
2. **Select the rule**:
   - Single term → Power Rule, exponential/log rules, trig rules
   - Two factors multiplied → Product Rule
   - Fraction of functions → Quotient Rule
   - Function inside a function → Chain Rule
   - Multiple rules may combine (e.g., Chain + Product)
3. **Differentiate** systematically
4. **Simplify** — Factor, combine fractions, reduce

### Integrals
1. **Recognize standard forms** — Power rule, basic trig, exponential, 1/x
2. **u-substitution** — Look for an inner function whose derivative appears in the integrand
3. **Integration by parts** — When the integrand is a product (use LIATE to choose u)
4. **Partial fractions** — For rational functions where the degree of numerator < degree of denominator
5. **Trig substitution** — For integrands involving √(a²-x²), √(a²+x²), or √(x²-a²)
6. **Don't forget +C** for indefinite integrals

### Optimization
1. **Draw a diagram** and label all quantities
2. **Identify the objective function** — What are you maximizing or minimizing?
3. **Write constraint equations** to reduce to one variable
4. **Differentiate** and find critical points (set f'(x) = 0)
5. **Verify** it's a max or min using the Second Derivative Test or Closed Interval Method
6. **Answer the question** — Compute the requested quantity, not just the critical point

### Related Rates
1. **Draw a diagram** and label all variables (use variables, not numbers, for changing quantities)
2. **List what you know**: given rates (dx/dt, etc.) and given values at the moment in question
3. **List what you want**: the unknown rate (dy/dt, etc.)
4. **Write a relationship** between the variables (geometric formula, Pythagorean theorem, etc.)
5. **Differentiate implicitly** with respect to time t
6. **Substitute** the known values and solve for the unknown rate
7. **Include units** in the final answer

## Verification Checklist
- [ ] Does the answer make sense in context? (positive area, reasonable speed, etc.)
- [ ] Do the units work out correctly?
- [ ] Does substituting back confirm the result?
- [ ] Does a graph or numerical estimate agree?
- [ ] Are there domain restrictions to consider?
