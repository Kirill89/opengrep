// This file contains the jobs to help release Semgrep on Homebrew
// (https://brew.sh/). Note that the Semgrep "recipe" is stored in
// https://github.com/Homebrew/homebrew-core/blob/master/Formula/s/semgrep.rb
// The goal of the jobs below is to modify semgrep.rb after a new
// release and open a PR to the homebrew-core repo with the modified semgrep.rb
// (e.g., https://github.com/Homebrew/homebrew-core/pull/157891 for 1.54.1)
//
// The jobs in this file are used from release.jsonnet and nightly.jsonnet,
// but it's also useful to have a separate workflow to trigger the
// homebrew release manually as we often get issues with homebrew.
//
// You can also call 'brew bump-formula-pr' locally on your mac to help debug
// issues. However, you'll first need to run:
//
//    $ brew tap Homebrew/core --force
//
// to set the right homebrew environment otherwise the
// 'brew bump-formula-pr ... semgrep' will fail with:
//
//    Error: No available formula with the name "semgrep".

// ----------------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------------

// TODO: hardcoded for now
local version = "1.55.1";
local tag = "v1.55.1";

local unless_dry_run = { };

// ----------------------------------------------------------------------------
// The jobs
// ----------------------------------------------------------------------------

local homebrew_core_pr_job = {
  name: 'Update on Homebrew-Core',
  // Needs to run after pypi released so brew can update pypi dependency hashes
  //needs: [
  //  'inputs',
  //  'sleep-before-homebrew',
  //],
  'runs-on': 'macos-12',
  steps: [
    // TODO: reuse actions.setup_python
    {
      uses: 'actions/setup-python@v4',
      id: 'python-setup',
      with: {
        'python-version': '3.10',
      },
    },
    {
      run: 'brew update',
    },
    {
      name: 'Open Brew PR',
      env: {
        HOMEBREW_GITHUB_API_TOKEN: '${{ secrets.SEMGREP_HOMEBREW_RELEASE_PAT }}',
      },
      run: |||
        brew bump-formula-pr --force --no-audit --no-browse --write-only \
          --message="semgrep %s" \
          --tag="%s" semgrep
      ||| % [version, tag],
    } + unless_dry_run,
    {
      name: 'Prepare Branch',
      env: {
        GITHUB_TOKEN: '${{ secrets.SEMGREP_HOMEBREW_RELEASE_PAT }}',
        R2C_HOMEBREW_CORE_FORK_HTTPS_URL: 'https://github.com/semgrep-release/homebrew-core.git',
      },
      run: |||
        cd "$(brew --repository)/Library/Taps/homebrew/homebrew-core"
        git status
        git diff
        git config user.name ${{ github.actor }}
        git config user.email ${{ github.actor }}@users.noreply.github.com
        gh auth setup-git
        git remote add r2c "${R2C_HOMEBREW_CORE_FORK_HTTPS_URL}"
        git checkout -b bump-semgrep-%s
        git add Formula/s/semgrep.rb
        git commit -m "semgrep %s"
      ||| % [version, version],
    },
    {
      name: 'Push Branch to Fork',
      env: {
        GITHUB_TOKEN: '${{ secrets.SEMGREP_HOMEBREW_RELEASE_PAT }}',
      },
      run: |||
        cd "$(brew --repository)/Library/Taps/homebrew/homebrew-core"
        git push --set-upstream r2c --force "bump-semgrep-%s"
      ||| % version,

    } + unless_dry_run,
    {
      name: 'Push to Fork',
      env: {
        GITHUB_TOKEN: '${{ secrets.SEMGREP_HOMEBREW_RELEASE_PAT }}',
        R2C_HOMEBREW_CORE_OWNER: 'semgrep-release',
      },
      run: |||
        gh pr create --repo homebrew/homebrew-core \
          --base master --head "${R2C_HOMEBREW_CORE_OWNER}:bump-semgrep-%s" \
          --title="semgrep %s" \
          --body "Bump semgrep to version %s"
      ||| % [version, version, version],
    } + unless_dry_run,
  ],
};

// ----------------------------------------------------------------------------
// The Workflow
// ----------------------------------------------------------------------------
{
  name: 'release-homebrew',
  on: {
    workflow_dispatch: null,
  },
  jobs: {
    'homebrew-core-pr': homebrew_core_pr_job,
  },
}