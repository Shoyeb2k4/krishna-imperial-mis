-- Revenue tax arithmetic: the canonical vectors, asserted in the database.
--
-- `app.revenue_compute` and Dart's `TaxRule.compute` are two implementations of one
-- specification (D-020). Two implementations of one rule is exactly the situation that
-- drifts, and "both were written from the same prose" is not evidence — which is the
-- lesson D-067 paid for with a real defect in the edit window.
--
-- So the vectors live **here**, once. This migration proves the server produces them, and
-- fails the deploy if it does not. `test/support/revenue_parity_vectors.dart` reads this
-- same table and requires Dart to agree, so neither side can be edited alone:
--
--   * add a vector here            -> Dart is checked against it automatically
--   * change an expected figure    -> Dart must change to match
--   * change either implementation -> the other side's assertion catches it
--
-- Every figure is integer paise. Half-up, applied once. No floating point is involved on
-- either side, which is why exact equality is the assertion and no tolerance appears.

do $$
declare
  v_case record;
  v_gross bigint;
  v_tax   bigint;
  v_net   bigint;
begin
  for v_case in
    select * from (values
      -- entered      rate    treatment      gross         tax        net        why
      (10000000::bigint,  500, 'inclusive',  10000000::bigint,  476190::bigint,  9523810::bigint, 'Restaurant, 1 lakh billed at 5% inclusive'),
      (1250000::bigint,   500, 'inclusive',  1250000::bigint,   59524::bigint,   1190476::bigint, 'Nandbhog, a routine day'),
      (6500000::bigint,   500, 'inclusive',  6500000::bigint,   309524::bigint,  6190476::bigint, 'Room, verified 5% inclusive'),
      (4034300::bigint,     0, 'none',       4034300::bigint,        0::bigint,  4034300::bigint, 'Banquet, verified without GST: the figure survives whole'),
      (4034300::bigint,     0, 'inclusive',  4034300::bigint,        0::bigint,  4034300::bigint, 'a CONFIGURED 0% is arithmetically identical to none, and financially a different statement'),
      (1::bigint,         500, 'inclusive',  1::bigint,              0::bigint,        1::bigint, 'one paisa: half-up rounds to nothing'),
      (7::bigint,         500, 'inclusive',  7::bigint,              0::bigint,        7::bigint, 'still below the half'),
      (33::bigint,        500, 'inclusive',  33::bigint,             2::bigint,       31::bigint, 'the smallest amount where half-up decides something'),
      (12345::bigint,     500, 'inclusive',  12345::bigint,        588::bigint,    11757::bigint, 'awkward paise'),
      (999999::bigint,    500, 'inclusive',  999999::bigint,     47619::bigint,   952380::bigint, 'just under a round lakh'),
      (100000001::bigint, 500, 'inclusive',  100000001::bigint, 4761905::bigint, 95238096::bigint, 'ten lakh and one paisa, well past 32-bit'),
      (10000000::bigint, 1800, 'exclusive',  11800000::bigint, 1800000::bigint, 10000000::bigint, 'exclusive: tax is added to what was typed'),
      (12345::bigint,    1800, 'exclusive',  14567::bigint,       2222::bigint,    12345::bigint, 'exclusive, rounding up')
    ) as t(entered, rate_bp, treatment, e_gross, e_tax, e_net, why)
  loop
    select c.gross, c.tax, c.net into v_gross, v_tax, v_net
      from app.revenue_compute(v_case.entered, v_case.rate_bp, v_case.treatment) c;

    if v_gross <> v_case.e_gross or v_tax <> v_case.e_tax or v_net <> v_case.e_net then
      raise exception
        'revenue_compute(%, %, %) = (%, %, %), expected (%, %, %) [%]',
        v_case.entered, v_case.rate_bp, v_case.treatment,
        v_gross, v_tax, v_net,
        v_case.e_gross, v_case.e_tax, v_case.e_net, v_case.why;
    end if;

    -- Reconciliation is a separate claim from correctness: a pair of wrong figures can
    -- still add up. Both are asserted.
    if v_tax + v_net <> v_gross then
      raise exception 'revenue_compute(%) does not reconcile: % + % <> %',
        v_case.entered, v_tax, v_net, v_gross;
    end if;
  end loop;
end $$;

-- Negative revenue is refused rather than computed. A management MIS records what was
-- billed; a negative sale is a correction, and corrections are void-and-re-enter (D-006).
do $$
begin
  begin
    perform * from app.revenue_compute(-1, 500, 'inclusive');
    raise exception 'negative revenue was computed instead of refused';
  exception
    when others then
      if sqlerrm = 'negative revenue was computed instead of refused' then
        raise;
      end if;
  end;
end $$;
