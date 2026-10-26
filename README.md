# JobIt

A native iOS app that makes job applications low-effort: a ranked daily queue, one-tap batch approval,
in-app autofill from a local answer bank, and drafted follow-ups you approve before anything is sent.

## How it works

- **Queue.** Pulls jobs from Greenhouse and Lever company boards on launch and on refresh. A set of
  boards with relevant openings is preloaded; add or remove companies under Criteria, then Job boards.
  Indeed has no public job feed, so "Import from Indeed" (Queue menu) reads its search results page by
  page in an in-app browser, with your keywords and location filled in, and adds the matches to your
  queue. If Indeed shows a human check, complete it in the window and tap Continue. If import is blocked,
  "Browse Indeed and save jobs myself" lets you open a job and tap "Save this job" instead. You can also
  paste any job link, and recruiter jobs go in the same way. LinkedIn is not supported yet.
  The default view is a swipe deck:
  right to approve, left for "not for me", up for later, with buttons and undo underneath. The list icon
  switches to a plain list. Sorted by fit to your skills, then fewest applicants (or newest, your choice).
- **Criteria.** Include and exclude keywords, locations, remote only, minimum salary, minimum employee
  rating, a company blocklist (military contractors pre-loaded, fully editable), and blocked terms.
- **Apply to all approved.** Opens each application inside the app. Links never leave the app: new-window
  links load in the same view and hand-offs to other apps are blocked. Autofill fills answers it knows (green),
  outlines questions you marked "ask every time" (orange), and saves new questions to your answer bank (red).
  You press Submit on the site yourself, then tap "Submitted" to log it.
- **Answers.** Your local answer bank. New questions land here once, then fill automatically.
- **Follow-ups.** A week after you apply, a draft appears. Edit it, open it in Mail or share it, then tap "I sent it".
  Nothing is ever sent automatically.
- **Recruiters.** A light tracker with a suggested check-in every few weeks.
- **Daily nudge.** One notification each morning saying what is waiting.

## Privacy

All data stays on the device in `jobit.json` in the app's Documents folder. No personal details are in this
repository; fill in your own on the Answers tab.

## Limits

- LinkedIn and Indeed have no public job feed, and employee-satisfaction ratings have no free official source,
  so those are manual (add by link, enter ratings yourself).
- Autofill covers text fields and dropdowns. Checkboxes, radio buttons and file uploads are left for you.
- Some sites block embedded browsers or require a CAPTCHA. Those need you in the loop.
- The build is unsigned. Sign it with your usual tool before installing.

## Build

CI builds on every change to `VERSION` (XcodeGen, then an unsigned IPA attached to a GitHub release).
