/// Luck that belongs to a day. Seeding a generator with 1, 2, 3 gives first
/// draws that follow a pattern, so anything chosen by the day (events,
/// catering orders) uses this well-mixed number instead.
int mixBits(int x) {
  x &= 0xFFFFFFFF;
  x ^= x >> 16;
  x = (x * 0x7feb352d) & 0xFFFFFFFF;
  x ^= x >> 15;
  x = (x * 0x846ca68b) & 0xFFFFFFFF;
  x ^= x >> 16;
  return x;
}

/// A number in [0, 1) that belongs to [day] and [salt] alone.
double dayLuck(int day, int salt) =>
    mixBits(mixBits(day * 0x9E3779B1 + salt) ^ 0x5bd1e995) / 4294967296;
