/// A scroll's text. Found lying in a zone, read once, then kept in the
/// journal. The id matches an item of kind `lore` in `itemDefs`.
class Lore {
  const Lore(this.title, this.lines);

  final String title;
  final List<String> lines;
}

const Map<String, Lore> loreDefs = {
  'scroll_orders': Lore('Orders for the south post', [
    'The Watch holds this post and trains every recruit that comes through. '
        'Tobin keeps it.',
    'The road to the city has been shut since the rock came down. We are too '
        'few to clear it.',
    'Learn what he teaches before you go further.',
  ]),
  'scroll_survey': Lore('Survey note, the pass', [
    'The roof of the pass came down in the night. The road is buried at the '
        'east end of the Deep.',
    'The warden\'s crew was on the far side. We have heard nothing from them '
        'since.',
    'We left blasting powder by the rubble. None of us would put a flame '
        'near it.',
  ]),
  'scroll_crew': Lore('Crew log, the quarry', [
    'We cut stone for the road until the pass came down. Half the crew went '
        'up the ladders to look for another way out.',
    'The golems were ours once. We set them to guard the cut. Nobody told '
        'them to stop.',
    'The lift from the rim to the floor lost its power cell in the fall. '
        'Until someone finds another, it is ladders or nothing.',
  ]),
  'scroll_warden': Lore('The warden\'s last order', [
    'I hold the gate. The road stays shut until I am relieved.',
    'If the gate is barred, it is barred from this side. Do not come up '
        'alone.',
  ]),
  'scroll_woodcutter': Lore('Note on a post', [
    'Mended the bridge again. The planks rot faster than I can cut them. '
        'Mara says leave it, but the road must stay open.',
    'Going to look at the pass. The ground has been groaning for days.',
  ]),
};
