# cgq

Canvas Group Quiz is a gleam CLI tool to create per-group quizzes.

## Table of Contents

1. [Usage](#usage)  
    - [List](#list)  
    - [Create](#create)  
    - [Fetch](#fetch)

## Usage

> [!IMPORTANT]
> You need to set the env var `CANVAS_API_TOKEN` to your API token.
> You can find the steps to get it [here](https://learninganalytics.ubc.ca/guides/get-started-with-the-canvas-api/).

If you want to change the domain for the canvas API, you can set the `CANVAS_API_DOMAIN` env var.

### List

To create a quiz for a course, you will need the `course_id`.
You can list the courses where you are `TA` or `Teacher` via

```sh
gleam run -- list courses <enrollment_type>
```

This will show you a table of **active** course names and IDs:

```
┌───────────────────────────────────────────────────────────────────────────────────┬────────┐
│                                       Name                                        │   ID   │
├───────────────────────────────────────────────────────────────────────────────────┼────────┤
│ COSC_O 310 101 2024W2 Software Engineering                                        │ ###### │
│ COSC_O 419O O_101 COSC_O 536K_101 2024W2 Topics in Computer Science - MINING DATA │ ###### │
└───────────────────────────────────────────────────────────────────────────────────┴────────┘
```

If you want to assign the created quiz to a specific `assignment_group`, you can use the list assignment group command.
The command is 

```sh
gleam run -- list assignment_groups <course_id>
```

It will show you the following table:

```
┌─────────────┬────────┐
│    Name     │   ID   │
├─────────────┼────────┤
│ Other       │ ###### │
│ Assignments │ ###### │
│ Project     │ ###### │
│ Quizzes     │ ###### │
└─────────────┴────────┘
```

To get an ID for a group, you can use the command

```sh
gleam run -- list groups <course_id>
```

Which will output something like:
```
┌────────────────────────┬────────┬─────────┐
│          Name          │   ID   │ Members │
├────────────────────────┼────────┼─────────┤
│ A                      │ ###### │       6 │
│ BrethooCodes           │ ###### │       5 │
│ Teams 15               │ ###### │       5 │
│ Teams 21               │ ###### │       5 │
│ The Stragglers         │ ###### │       5 │
└────────────────────────┴────────┴─────────┘
```

A course can have more than one group set (Canvas calls them group
categories). `create` defaults to **every** group in the course, so if the
course uses groups for more than one thing, scope to a single set. List the
sets to get a `group_category_id`:

```sh
gleam run -- list group_categories <course_id>
```

and pass it to `list groups` to see just that set, or to `create` (below) to
make quizzes for just that set:

```sh
gleam run -- list groups <course_id> --group_category_id <group_category_id>
```

### Create

You can create a quiz using the following command:

> [!IMPORTANT]
> The quiz questions are read from a TOML template, by default
> [`./questions.toml`](./questions.toml). Use `--questions <path>` to point at
> a different file. The shipped template documents the format, including the
> `distribute` block that expands into one point-distribution question per
> group member.

Check a template without contacting Canvas (no token needed). It exits 0 on a
valid template, or prints an error pointing at the problem and exits 1:

```sh
gleam run -- validate                  # checks ./questions.toml
gleam run -- validate ./my-template.toml
```

```sh
gleam run -- create 155027 \
    --title "Week 13" \
    --description "Weekly evaluations." \
    --quiz_type "graded_survey" \
    --assignment_group_id "538476" \
    --unlock_at "2025-04-04 23:59.999-8:00" \
    --due_at "2025-04-09 23:59.999-8:00" \
    --published "True" \
    --points 2


gleam run -- create "<course_id>" \
    --title "Week 5" \
    --description "Weekly evaluations." \
    --group_category_id "<group_category_id>" \
    --assignment_group_id "<assignment_group_id>" \
    --quiz_type "graded_survey" \
    --unlock_at "2025-02-07 23:59.999-8:00" \
    --due_at "2025-02-14 23:59.999-8:00" \
    --published "True" \
    --points 2
```

> [!NOTE]
> The group name will be added to the quiz title.

> [!IMPORTANT]
> Without `--group_category_id`, `create` makes a quiz for **every** group in
> the course across all group sets. Pass it (from `list group_categories`) to
> scope to one set. Use `--group_id` instead to target a single group.

And it will print out the progress:
```
Creating quiz for group <group_name>...
Created quiz with ID <quiz_id>.  Adding quiz questions...
Questions created.  Assigning quiz to group...
Quiz assigned.
```

You can also make a quiz for a single group using the `<group_id>` option:

```sh
gleam run -- create <course_id> \
    --group_id "<group_name>" \
    --title "Week 5" \
    --description "Weekly evaluations." \
    --quiz_type "graded_survey" \
    --assignment_group_id "<assignment_group_id>" \
    --due_at "2025-02-14 23:59.999-8:00" \
    --unlock_at "2025-02-07 23:59.999-8:00" \
    --published "False"
```

### Fetch

You will probably want to see the results for the quizzes. The `fetch` command
has three subcommands:

```sh
gleam run -- fetch feedback <course_id> <quiz_title>   # print essay feedback as a table
gleam run -- fetch evals <course_id> [filepath]        # write per-group peer-eval ratings to CSV
gleam run -- fetch percent <course_id> [filepath]      # write per-student survey completion rates to CSV
```

#### `fetch feedback`

Prints the optional essay feedback for every submission whose quiz title matches
`<quiz_title>`. It fetches all matching quizzes in the course, so a title of
"Week 5" returns every "Week 5: \<group\>" quiz:

```sh
gleam run -- fetch feedback <course_id> "Week 5"
```

Which will take some time as it fetches all the results. It will output

```
Fetching...
┌───────────────────────┬────────────────────────────────┬──────────────────────────────────────────┐
│     Student Name      │           Quiz Title           │                Complaint                 │
├───────────────────────┼────────────────────────────────┼──────────────────────────────────────────┤
│ #### ######           │ Week 5: Group 1                │ ### #### ## ### ## ###### ## ##########  │
│                       │                                │                                          │
│ ###### ####           │ Week 5: Group 1                │ ### #### ### ######### # #######, ###### │
│                       │                                │ ### #### ###### ##### ###### ## ## ####  │
│                       │                                │ ###### ## ### ### #### #### ### ### #### │
│                       │                                │ #### ## #### #####, ### ## ## ####### ## │
│                       │                                │ #### ##### ## #### # ##########          │
│                       │                                │ ######### ##### ###. # ##### ######, #   │
│                       │                                │ #### ##### # ########## #### ### ### ### │
│                       │                                │ #### ### ######## # ###### ##.           │
│                       │                                │                                          │
│ ##### ######          │ Week 5: Group 2                │ ## #### ####### ### ###### #### #### ### │
│                       │                                │ ### ##### #####. #### ## ### ## ######   │
│                       │                                │ #### #### ######## ## ######.            │
│                       │                                │                                          │
└───────────────────────┴────────────────────────────────┴──────────────────────────────────────────┘
```

#### `fetch evals`

Aggregates the peer-evaluation point distributions for every quiz whose title
matches `--title_prefix` (default `"Week "`), normalizes them per group, and
writes the result to CSV (defaults to `./results.csv`) with one column per
matching base title:

```sh
gleam run -- fetch evals <course_id> ./results.csv
gleam run -- fetch evals <course_id> ./results.csv --title_prefix "Sprint "
```

The weeks are discovered from the quizzes that exist — there is no hardcoded
range. This assumes quizzes are titled `<title_prefix><...>: <group>` (the
`<base>: <group>` shape `create` produces).

The answers are parsed back out of the quizzes using the same question template
the quizzes were created with (`--questions`, default `./questions.toml`) — if
you created the quizzes with a custom template, fetch with that same file.

#### `fetch percent`

Writes the fraction of weekly surveys each student has completed to CSV (defaults
to `./percent_of_surveys_completed.csv`), counting every quiz whose title matches
`--title_prefix` (default `"Week "`):

```sh
gleam run -- fetch percent <course_id> ./percent_of_surveys_completed.csv
```

## Development

To build locally you can use
```sh
gleam clean
gleam run
```

The test suite needs no Canvas credentials: `gleam test` runs the unit tests
plus an end-to-end test that drives `create`, `fetch evals`, and
`fetch percent` against an in-process mock Canvas server
(`test/mock_canvas.erl`). `nix flake check` runs the same suite hermetically.

To test against real Canvas without touching production, UBC's beta instance
(`https://ubc.beta.instructure.com`) is a sandbox copy of production refreshed
weekly — generate a token there and set
`CANVAS_API_DOMAIN="https://ubc.beta.instructure.com/api/v1"`.

To build the release binary, use `nix`:
```sh
nix build              # default package
nix build .#release    # burrito-packaged binary
```

The release target uses [burrito](https://github.com/burrito-elixir/burrito) (via
[nix-gleam-burrito](https://github.com/ethanthoma/nix-gleam-burrito)) to build a
self-contained executable into `burrito_out`.

Burrito caches the unpacked release, so before rebuilding you have to clear the cache:
```sh
burrito_out/<binary_name> maintenance uninstall
```
