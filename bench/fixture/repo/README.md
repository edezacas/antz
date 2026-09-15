# toysize

A toy unit-conversion utility. This repository is the checked-in fixture
the antz benchmark harness materializes per repetition; the benchmark
request extends it with one more conversion.

## Usage

    sh toysize.sh cm-to-inch <centimeters>

Prints the length in inches (centimeters divided by 2.54), rounded to
six decimal places.

A `km-to-mile` conversion is not implemented yet.
