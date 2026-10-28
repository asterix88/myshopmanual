import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/screens/unit_tabs.dart';

void main() {
  test('Komatsu titles in capitals read like CAT titles', () {
    expect(tidyTitle('CHECK LEVEL OF BATTERY ELECTROLYTE'), 'Check Level of Battery Electrolyte');
    expect(tidyTitle('CHECK OIL LEVEL IN DAMPER CASE, ADD OIL'), 'Check Oil Level in Damper Case, Add Oil');
    expect(tidyTitle('REPLACE PPC FILTER ELEMENT'), 'Replace PPC Filter Element');
    expect(tidyTitle('LUBRICATING'), 'Lubricating');
    expect(tidyTitle('CLEAN AND INSPECT PRE-CLEANER'), 'Clean and Inspect Pre-Cleaner');
    // CAT titles and numbers stay as they are.
    expect(tidyTitle('Bucket Linkage - Lubricate'), 'Bucket Linkage - Lubricate');
    expect(tidyTitle('EVERY 250 HOURS SERVICE'), 'Every 250 Hours Service');
  });
}
