/* Which of the eight steps you are in.
 *
 * The rail itself is CSS: it is in the flow after the contents list and pins
 * with position: sticky. This file only adds the highlight, so with scripting
 * off the page loses an affordance and keeps eight working links.
 *
 * Two things here are not obvious. An IntersectionObserver on the steps alone
 * answers "is this on screen", which is the wrong question when a step is
 * taller than the window -- every one of these is -- because the answer is
 * often "none of them" or "two of them". So the observer is used purely as a
 * cheap change signal, and the decision is made by measuring: the current step
 * is the last one whose top has passed the line under the rail. That also
 * settles ties in reading order rather than by intersection ratio, which is
 * what a reader means by "where am I".
 *
 * The other is that the act name is read from the DOM rather than duplicated
 * here, so the grouping lives in exactly one place -- steps.py -- and this
 * cannot drift out of step with the page it is labelling.
 */
(function () {
  var rail = document.querySelector('.rail');
  if (!rail) return;

  var links = [].slice.call(rail.querySelectorAll('a[href^="#"]'));
  var label = rail.querySelector('.rail-act');
  var steps = links.map(function (a) {
    return document.getElementById(decodeURIComponent(a.hash.slice(1)));
  });
  if (steps.some(function (s) { return !s; })) return;

  var acts = links.map(function (a) { return a.closest('ol').dataset.act; });
  var toc = document.querySelector('.toc');
  var last = steps[steps.length - 1];
  var current = -1, shown = null;

  rail.hidden = false;   // the markup ships hidden; without this file it stays so

  function paint() {
    // Show it only over the steps: before that the contents list is still on
    // screen saying the same thing, and after the last step there is nothing
    // left to be lost in. Measured against the rail's own height rather than a
    // constant, so changing its padding cannot put the two out of step.
    var h = rail.offsetHeight;
    var on = (!toc || toc.getBoundingClientRect().bottom < 0) &&
             last.getBoundingClientRect().bottom > h;
    if (on !== shown) { shown = on; rail.classList.toggle('on', on); }

    // the line sits just below the bar, so a step counts as current once its
    // heading has actually gone under it
    var line = h + 8;
    var i = -1;
    for (var n = 0; n < steps.length; n++) {
      if (steps[n].getBoundingClientRect().top <= line) i = n;
    }
    if (i === current) return;
    current = i;
    links.forEach(function (a, n) {
      if (n === i) a.setAttribute('aria-current', 'step');
      else a.removeAttribute('aria-current');
    });
    // before the first step, name the act the reader is heading into
    label.textContent = acts[i < 0 ? 0 : i];
  }

  // the observer is a change signal, not the decision: it fires when any step
  // edge crosses the viewport, which is exactly when the answer can change
  var io = new IntersectionObserver(paint, { threshold: [0, 1] });
  steps.forEach(function (s) { io.observe(s); });

  // ...and a scroll listener for the long middle of a tall step, where no
  // edge crosses anything for thousands of pixels. One frame at a time: a
  // fast scroll fires this far more often than the screen refreshes, and
  // without the flag every one of those events queues its own callback.
  var queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; paint(); });
  }
  addEventListener('scroll', schedule, { passive: true });
  addEventListener('resize', paint, { passive: true });

  // A background tab gets no animation frames, so a scroll that happens while
  // the page is hidden -- restoring a session, or a link into the middle of it
  // -- lands with the highlight never repainted, and nothing fires again until
  // the reader scrolls. Paint on the way back in. (This page's sibling learned
  // the same lesson the hard way: see the rAF note in demo.js.)
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) paint();
  });
  addEventListener('pageshow', paint);
  paint();
})();
