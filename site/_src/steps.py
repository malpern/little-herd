# The eight steps, and the homepage card for each.
# ONE source: the guide renders from `heading`/`what`/`figure`/`tool`/`body`,
# the homepage card from `card`, and both take the tool name and the anchor
# from the same entry -- which is what stops the two pages drifting apart.
# Extracted from the shipped pages rather than retyped, so the builder
# reproduces what was already live.

STEPS = [{'id': 'reach', 'ask': ('Tailscale', 'I have a few Macs, a Linux box and a NAS at home that I want to reach from anywhere. Explain what Tailscale is and how it differs from a VPN or port forwarding, then walk me through installing and signing in on macOS and on Linux, turning on MagicDNS so each machine has a name, and checking it works from off my home network. Cover machine key expiry and why I should disable it for a headless machine. Give exact commands.'), 'logo': 'tailscale',
  'n': 1,
  'heading': 'Reach any machine from anywhere',
  'what': 'One name per machine that works from the sofa, from a hotel, and from another machine '
          'in the herd &mdash; with nothing exposed to the open internet.',
  'figure': '      <figure class="fig fig-ring">\n'
            '        <img class="f1" src="images/herdware/chick-laptop.png" alt=""><img class="f2" '
            'src="images/herdware/calf-mini.png" alt=""><img class="f3" '
            'src="images/herdware/ox-gpu.png" alt="">\n'
            '        <svg class="s-wire" viewBox="0 0 420 150" preserveAspectRatio="xMidYMid '
            'meet">\n'
            '          <path class="s-route" d="M210 22 C 350 22, 400 128, 210 128 C 20 128, 70 '
            '22, 210 22 Z"/>\n'
            '          <path class="s-pulse" d="M210 22 C 350 22, 400 128, 210 128 C 20 128, 70 '
            '22, 210 22 Z"/>\n'
            '        </svg>\n'
            '        <figcaption>One name each, reachable from anywhere.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://tailscale.com',
           'name': 'Tailscale',
           'note': 'Free for personal use',
           'go': 'tailscale.com &#8599;'},
  'body': '      <p>This one is first because everything below it assumes you can reach\n'
          '        the machine at all. Install on each one, sign in with the same account,\n'
          '        turn on MagicDNS, and you are done &mdash; no port forwarding, no static\n'
          '        IP, no router configuration, and nothing listening on the public\n'
          '        internet.</p>\n'
          '      <p class="trap"><b>The trap:</b> a machine&rsquo;s key expires by default,\n'
          '        usually in about six months. A laptop you use daily just asks you to sign\n'
          '        in again. <em>An unattended box silently drops off the network</em> and\n'
          '        you discover it the next time you need it, which is the worst possible\n'
          '        moment. Disable key expiry for anything headless.</p>\n'
          '      <p class="trap"><b>And:</b> a <code>.local</code> name is mDNS. It resolves\n'
          '        at home and nowhere else, so a setup tested only on the sofa looks\n'
          '        finished and fails the first time you leave the house. Use the tailnet\n'
          '        name everywhere, including in scripts.</p>',
  'card': {'heading': 'Reach any of them from anywhere',
           'text': 'One name per machine that works from the sofa or a hotel, with nothing exposed '
                   'to the open internet.',
           'tool': 'Tailscale'}},
 {'id': 'connect', 'ask': ('SSH and ~/.ssh/config', 'Teach me to reach several home machines by short names over SSH. Cover generating a key, copying it with ssh-copy-id, writing Host / HostName / User entries in ~/.ssh/config, using Include to share that config across machines, the file permissions SSH requires, and why a key used by a scheduled job must not have a passphrase. macOS and Linux, with exact commands.'), 'shot': ('ssh.png', 'Landing on another machine, from its short name.'), 'logo': 'ssh',
  'n': 2,
  'heading': 'Get onto any machine with one short command',
  'what': '<code>ssh mini</code> instead of an address you have to remember, and a new machine '
          'that inherits the whole herd rather than being set up by hand.',
  'figure': '      <figure class="fig fig-fan">\n'
            '        <img class="f1" src="images/herdware/chick-laptop.png" alt=""><img class="f2" '
            'src="images/herdware/calf-mini.png" alt=""><img class="f3" '
            'src="images/herdware/ox-gpu.png" alt=""><img class="f4" '
            'src="images/herdware/piglet-nas.png" alt="">\n'
            '        <svg class="s-wire" viewBox="0 0 420 210" preserveAspectRatio="xMidYMid '
            'meet">\n'
            '          <path class="s-route" d="M92 96 C 170 62, 240 42, 320 36"/>\n'
            '          <path class="s-pulse" d="M92 96 C 170 62, 240 42, 320 36"/>\n'
            '          <path class="s-route" d="M92 96 C 170 100, 240 104, 320 105"/>\n'
            '          <path class="s-pulse d1" d="M92 96 C 170 100, 240 104, 320 105"/>\n'
            '          <path class="s-route" d="M92 96 C 170 136, 240 166, 320 174"/>\n'
            '          <path class="s-pulse d2" d="M92 96 C 170 136, 240 166, 320 174"/>\n'
            '        </svg>\n'
            '        <figcaption>One command, every machine.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://man.openbsd.org/ssh_config',
           'name': 'SSH and <code>~/.ssh/config</code>',
           'note': 'Already on every Mac and Linux machine',
           'go': 'ssh_config(5) &#8599;'},
  'body': '      <p>Generate a key, copy it over with <code>ssh-copy-id</code>, then write\n'
          '        the machine down in <code>~/.ssh/config</code> once:</p>\n'
          '      <pre><code>Host mini\n'
          '  HostName mini.your-tailnet.ts.net\n'
          '  User you</code></pre>\n'
          '      <p>That name now works everywhere SSH does &mdash;\n'
          '        <code>scp file mini:</code>, <code>rsync</code>, an editor&rsquo;s remote\n'
          '        mode, a backup job. Keep the file in your dotfiles and\n'
          '        <code>Include</code> it rather than editing it per machine.</p>\n'
          '      <p class="trap"><b>The trap:</b> a key with a passphrase cannot be used by\n'
          '        anything that runs unattended &mdash; there is nobody there to type it.\n'
          '        Keep your passphrase key for sitting-at-the-keyboard work, and give\n'
          '        scheduled jobs their own passphrase-free key, authorised for exactly the\n'
          '        one link it needs. A single key for both is how a convenience becomes\n'
          '        the blast radius.</p>\n'
          '      <p class="trap"><b>And:</b> SSH silently ignores a config or key file that\n'
          '        other users can write. Wrong permissions do not produce an error that\n'
          '        says &ldquo;permissions&rdquo; &mdash; they produce\n'
          '        <code>Permission denied (publickey)</code>, which sends you off\n'
          '        debugging the key instead. <code>chmod 600</code>.</p>',
  'card': {'heading': 'Get on with one short command',
           'text': 'The same way in to every machine, and a new one inherits the herd instead of '
                   'being set up by hand.',
           'tool': 'SSH'}},
 {'id': 'tools', 'video': ('DevOps Toolbox', '~/.dotfiles 101: A Zero to Configuration Hero Blueprint', 'WpQ5YiM7rD4'), 'ask': ('Homebrew and a Brewfile', 'Show me how to keep the same command-line tools on several Macs using Homebrew and a Brewfile. Cover brew bundle dump and brew bundle, keeping the Brewfile in a dotfiles repo, the difference between formulae and casks and why casks belong only on machines with a screen, and why a cron job or an ssh command cannot find brew on Apple silicon unless it sets PATH itself. Exact commands.'), 'shot': ('brew.png', 'One command, and the machine has your toolkit.'), 'logo': 'homebrew',
  'n': 3,
  'heading': 'Arrive on a machine and find your tools already there',
  'what': 'Every machine carries the same kit, so the one you connect to is somewhere you can work '
          'rather than somewhere you have to set up first.',
  'figure': '      <figure class="fig fig-kit">\n'
            '        <img class="f1" src="images/herdware/chick-laptop.png" alt=""><img class="f2" '
            'src="images/herdware/calf-mini.png" alt=""><img class="f3" '
            'src="images/herdware/ox-gpu.png" alt="">\n'
            '        <span class="kit k1"><i></i><i></i><i></i></span>\n'
            '        <span class="kit k2"><i></i><i></i><i></i></span>\n'
            '        <span class="kit k3"><i></i><i></i><i></i></span>\n'
            '        <figcaption>The same kit, wherever you land.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://brew.sh',
           'name': 'Homebrew and a Brewfile',
           'note': 'Free and open source',
           'go': 'brew.sh &#8599;'},
  'body': '      <p>A herd whose members each have a different half of your toolkit is\n'
          '        still a pile. Dump what you have into a list, keep the list in your\n'
          '        dotfiles, and install from it on every machine:</p>\n'
          '      <pre><code>brew bundle dump --file ~/dotfiles/Brewfile\n'
          'brew bundle --file ~/dotfiles/Brewfile</code></pre>\n'
          '      <p>A new machine goes from bare to useful in one command, and when you\n'
          '        adopt a tool you add it once.</p>\n'
          '      <p class="trap"><b>The trap:</b> a non-interactive shell &mdash; a cron\n'
          '        job, a scheduled task, or <code>ssh machine some-command</code> &mdash;\n'
          '        does not read your profile, so on Apple silicon it never gets\n'
          '        <code>/opt/homebrew/bin</code> on its <code>PATH</code>. Everything works\n'
          '        when you are typing and fails when it runs by itself, reporting\n'
          '        <em>command not found</em> for something you can plainly see installed.\n'
          '        Scripts should set their own PATH rather than assume yours.</p>\n'
          '      <p class="trap"><b>And:</b> casks are GUI applications. Put them on the\n'
          '        machine you sit in front of, not the headless one, where they are weight\n'
          '        with nothing to show.</p>',
  'card': {'heading': 'Find your tools already there',
           'text': 'The machine you connect to is somewhere you can work, not somewhere you have '
                   'to set up first.',
           'tool': 'Homebrew'}},
 {'id': 'detach', 'video': ('typecraft', 'I Love TMUX and you should too', '-B5VDp50daI'), 'ask': ('tmux', 'I am new to tmux and want the minimum that lets me start a long job on a remote machine and disconnect without killing it. Cover installing it, new / detach / attach, the difference between sessions, windows and panes, listing and killing sessions, and the common mistake of running tmux on my laptop instead of on the remote machine. Exact commands and key bindings.'), 'shot': ('tmux.png', 'The green bar is tmux. The work is running on the far machine.'), 'logo': 'tmux',
  'n': 4,
  'heading': 'Start something on another machine and walk away',
  'what': 'Close the lid, lose the connection, come back tomorrow &mdash; the work carries on, '
          'because it was never running on your laptop.',
  'figure': '      <figure class="fig fig-away">\n'
            '        <img class="f1" src="images/herdware/chick-laptop.png" alt=""><img class="f2" '
            'src="images/herdware/calf-mini.png" alt="">\n'
            '        <svg class="s-wire" viewBox="0 0 420 150" preserveAspectRatio="xMidYMid '
            'meet">\n'
            '          <circle class="ring-track" cx="286" cy="70" r="30"/>\n'
            '          <circle class="ring-spin"  cx="286" cy="70" r="30"/>\n'
            '        </svg>\n'
            '        <figcaption>You leave. It carries on.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://github.com/tmux/tmux/wiki/Getting-Started',
           'name': 'tmux',
           'note': 'Free and open source &middot; <code>brew install tmux</code>',
           'go': 'tmux wiki &#8599;'},
  'body': '      <p>The trick is that the session belongs to the far machine, not to your\n'
          '        connection. You are attaching to something already running there:</p>\n'
          '      <pre><code>ssh mini\n'
          'tmux new -s work      # start it there\n'
          '# Ctrl-b then d       # detach; the work keeps going\n'
          'tmux attach -t work   # come back, from anywhere</code></pre>\n'
          '      <p>This is the single biggest change in how remote machines feel. They\n'
          '        stop being fragile.</p>\n'
          '      <p class="trap"><b>The trap:</b> tmux has to run <em>on the remote\n'
          '        machine</em>. Starting it in a local terminal and then SSH-ing from\n'
          '        inside gives you a session that dies with your connection, which is the\n'
          '        exact thing you were trying to prevent. SSH first, then tmux.</p>',
  'card': {'heading': 'Start something and walk away',
           'text': 'Close the lid and the work carries on, because it was never running on your '
                   'laptop.',
           'tool': 'tmux'}},
 {'id': 'screen', 'ask': ('macOS Screen Sharing', 'Explain how to use the Screen Sharing built into macOS to control another Mac on my network. Cover turning it on in System Settings, connecting with Finder\'s Connect to Server and a vnc:// address, when it is the right tool rather than SSH, and why macOS privacy prompts such as Screen Recording and Full Disk Access can only be granted on that machine\'s own screen.'), 'shot': ('connect.png', 'Finder&rsquo;s Connect to Server, waiting for a machine name.'), 'logo': 'screen',
  'n': 5,
  'heading': 'See and use another machine&rsquo;s screen from this one',
  'what': 'The actual desktop of the box in the closet, for the things that only exist on a screen '
          '&mdash; a permission dialog, an installer, a first run.',
  'figure': '      <figure class="fig fig-screen">\n'
            '        <img class="f1" src="images/herdware/chick-laptop.png" alt="">\n'
            '        <span class="pane"><img src="images/herdware/calf-mini.png" alt=""></span>\n'
            '        <svg class="s-wire" viewBox="0 0 420 150" preserveAspectRatio="xMidYMid '
            'meet">\n'
            '          <path class="s-route" d="M126 78 L 236 78"/>\n'
            '          <path class="s-pulse" d="M126 78 L 236 78"/>\n'
            '        </svg>\n'
            '        <figcaption>Its desktop, on your screen.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://support.apple.com/guide/mac-help/screen-sharing-overview-mh14066/mac',
           'name': 'Screen Sharing',
           'note': 'Built into macOS &mdash; nothing to install',
           'go': 'Apple support &#8599;'},
  'body': '      <p>In Finder, <b>Go &rarr; Connect to Server</b> (<kbd>&#8984;K</kbd>) and\n'
          '        enter <code>vnc://mini</code>. You get the actual desktop.</p>\n'
          '      <p>Most of the time SSH is better &mdash; faster, scriptable, works on a\n'
          '        bad connection. But some things only exist on the screen: a permission\n'
          '        dialog, an installer, a first run, an app that has decided to show you a\n'
          '        window. Those are not stubbornness on your part; they genuinely cannot be\n'
          '        done over a shell.</p>\n'
          '      <p class="trap"><b>The trap:</b> macOS privacy prompts appear on the\n'
          '        machine&rsquo;s own screen and nowhere else, so a script that needs\n'
          '        Screen Recording or Full Disk Access will sit there having silently\n'
          '        failed while you stare at an SSH session with no error in it. Grant those\n'
          '        over Screen Sharing, once, before automating anything that needs them.</p>\n'
          '      <p class="trap"><b>And the honest limit:</b> if a machine is wedged before\n'
          '        the operating system is up, neither SSH nor Screen Sharing can reach it,\n'
          '        because both are software running inside the thing that has not started.\n'
          '        That is what a hardware KVM is for, and it is the only thing that is.</p>',
  'card': {'heading': 'Use another machine&rsquo;s screen',
           'text': 'For the things that only exist on a screen &mdash; a permission dialog, an '
                   'installer, a first run.',
           'tool': 'Screen Sharing'}},
 {'id': 'agents', 'video': ('typecraft', 'I&rsquo;m ditching tmux for herdr!', 'yQDARWdrPeY'), 'ask': ('Herdr', 'Explain Herdr (github.com/herdrdev/herdr), a terminal multiplexer built for AI coding agents. How do I install it on macOS, how does it differ from tmux, how do I run several Claude Code or Codex agents in panes and see at a glance which one is working, blocked or waiting on me, and how do its sessions detach and reattach over SSH?'), 'logo': 'panes',
  'n': 6,
  'heading': 'Run several agents at once and see which one is waiting on you',
  'what': 'Each agent in its own pane, marked working, blocked or done, on a session you can '
          'detach from and pick up later over SSH.',
  'figure': '      <figure class="fig fig-agents">\n'
            '        <img class="f1" src="images/herdware/calf-mini.png" alt="">\n'
            '        <span class="lanes">\n'
            '          <b class="run"></b><b class="wait"></b><b class="done"></b><b '
            'class="run2"></b>\n'
            '        </span>\n'
            '        <figcaption>Working, waiting, done &mdash; at a glance.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://github.com/herdrdev/herdr',
           'name': 'Herdr',
           'note': 'Free and open source',
           'go': 'github.com/herdrdev/herdr &#8599;'},
  'body': '      <p>Once coding agents are doing real work, the question stops being\n'
          '        &ldquo;is it done&rdquo; and becomes &ldquo;which of these is waiting on\n'
          '        me.&rdquo; tmux will happily keep four agents alive and tell you nothing\n'
          '        about any of them; Herdr shows each one as working, blocked, or done, and\n'
          '        its sessions detach and reattach over SSH the same way.</p>\n'
          '      <p>It runs the agents on <em>one</em> machine, which is the natural\n'
          '        complement to seeing them across all of them &mdash; and it is where\n'
          '        Little Herd stops being optional.</p>',
  'card': {'heading': 'Run several agents at once',
           'text': 'And see at a glance which of them is working, which is done, and which is '
                   'waiting on you.',
           'tool': 'Herdr'}},
 {'id': 'backup', 'ask': ('Time Machine and restic', 'Show me how to back up several Macs over the network to one NAS with Time Machine, and how to back up a Linux machine to the same NAS with restic so the destination only ever stores encrypted data. Cover choosing the destination, scheduling, actually testing a restore, and why append-only or immutable backups matter if a machine is compromised. Exact commands.'), 'logo': 'backup',
  'n': 7,
  'heading': 'Back every machine up to one place',
  'what': 'One destination that all of them write to, so the box in\n'
          '        the closet stops being storage you own and becomes the machine that\n'
          '        holds everything.',
  'figure': '      <figure class="fig fig-backup">\n'
            '        <img class="f1" src="images/herdware/chick-laptop.png" alt="">\n'
            '        <img class="f2" src="images/herdware/calf-mini.png" alt="">\n'
            '        <img class="f3" src="images/herdware/ox-gpu.png" alt="">\n'
            '        <img class="f4" src="images/herdware/piglet-nas.png" alt="">\n'
            '        <svg class="s-wire" viewBox="0 0 420 210" preserveAspectRatio="xMidYMid '
            'meet">\n'
            '          <path class="s-route" d="M60 60 C 140 70, 220 96, 300 112"/>\n'
            '          <path class="s-pulse" d="M60 60 C 140 70, 220 96, 300 112"/>\n'
            '          <path class="s-route" d="M60 118 C 140 120, 220 118, 300 116"/>\n'
            '          <path class="s-pulse d1" d="M60 118 C 140 120, 220 118, 300 116"/>\n'
            '          <path class="s-route" d="M60 176 C 140 166, 220 138, 300 122"/>\n'
            '          <path class="s-pulse d2" d="M60 176 C 140 166, 220 138, 300 122"/>\n'
            '        </svg>\n'
            '        <figcaption>Everything lands in one place.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://support.apple.com/guide/mac-help/back-up-your-mac-with-time-machine-mh35860/mac',
           'name': 'Time Machine',
           'note': 'Built into macOS &middot; point it at a network volume',
           'go': 'Apple support &#8599;'},
  'body': '      <p>Every Mac in the herd can back up over the network to the same NAS\n'
          '        share &mdash; no cable, no swapping a drive between machines. For a Linux\n'
          '        box, or for anything you would rather the NAS could not read,\n'
          '        <a href="https://restic.net">restic</a> encrypts on the machine and\n'
          '        sends only ciphertext, so the destination stores your backups without\n'
          '        being able to open them.</p>\n'
          '      <p class="trap"><b>The trap:</b> a backup you have never restored from is\n'
          '        not a backup, it is a belief. Restore one file, deliberately, the week\n'
          '        you set it up &mdash; the failure you are guarding against is the one\n'
          '        where the job has been reporting success for a year into a destination\n'
          '        that quietly stopped mounting.</p>\n'
          '      <p class="trap"><b>And:</b> whatever key writes the backups can usually\n'
          '        delete them, so a machine that is compromised can take its own history\n'
          '        with it. If the destination can be made append-only, do it; if it\n'
          '        cannot, at least know that is the gap rather than assuming a copy\n'
          '        somewhere is the same as a copy you cannot lose.</p>',
  'card': {'heading': 'Back every machine up to one place',
           'text': 'One destination holding all of it, so the box in the closet becomes the '
                   'machine that matters.',
           'tool': 'Time Machine'}},
 {'id': 'alerts', 'ask': ('Healthchecks.io', 'Teach me to find out when an unattended machine or a scheduled backup stops running. Explain dead man\'s switch monitoring with Healthchecks.io, how to ping a check from a cron job or a launchd agent on macOS, how to alert on a job that has not reported rather than only on a machine that is down, why a machine should not be the thing that monitors itself, and what a hosted check catches that a self-hosted one cannot.'), 'logo': 'beat',
  'n': 8,
  'heading': 'Find out when one of them stops',
  'what': 'An unattended machine that dies is only a problem the\n'
          '        moment you need it &mdash; which is always the worst moment. Have it\n'
          '        tell you instead.',
  'figure': '      <figure class="fig fig-alert">\n'
            '        <img class="f1" src="images/herdware/calf-mini.png" alt="">\n'
            '        <img class="f2" src="images/herdware/ox-gpu.png" alt="">\n'
            '        <span class="beat b1"></span>\n'
            '        <span class="beat b2"></span>\n'
            '        <svg class="s-wire" viewBox="0 0 420 150" preserveAspectRatio="xMidYMid '
            'meet">\n'
            '          <path class="s-route" d="M104 66 C 170 40, 230 40, 296 66"/>\n'
            '          <path class="s-pulse" d="M104 66 C 170 40, 230 40, 296 66"/>\n'
            '          <path class="s-route" d="M296 108 C 230 134, 170 134, 104 108"/>\n'
            '          <path class="s-pulse d1" d="M296 108 C 230 134, 170 134, 104 108"/>\n'
            '        </svg>\n'
            '        <figcaption>Each one checks on the other.</figcaption>\n'
            '      </figure>',
  'tool': {'url': 'https://healthchecks.io',
           'name': 'Healthchecks.io',
           'note': 'Free tier and open source',
           'go': 'healthchecks.io &#8599;'},
  'body': '      <p>Or self-host\n'
          '        <a href="https://github.com/louislam/uptime-kuma">Uptime Kuma</a> on a\n'
          '        machine in the herd, with the caveat below. The shape that works either\n'
          '        way is a dead man&rsquo;s switch: each machine, and\n'
          '        each scheduled job, checks in after a successful run. Nothing arriving\n'
          '        is the alarm. That catches the failures a ping never will &mdash; a\n'
          '        machine that is up and answering while the backup on it has not run\n'
          '        since March.</p>\n'
          '      <p class="trap"><b>The trap:</b> do not let a machine watch itself. A box\n'
          '        that reports on its own backups goes quiet at exactly the moment its\n'
          '        report matters, and silence from something that only ever spoke when it\n'
          '        was healthy is indistinguishable from everything being fine. Have\n'
          '        another machine hold the expectation.</p>\n'
          '      <p class="trap"><b>And the honest limit:</b> if two machines watch each\n'
          '        other and the power goes out, both are down and neither can tell you.\n'
          '        Only something outside the house closes that, which is the argument for\n'
          '        a hosted check over one you run at home &mdash; and the reason to know\n'
          '        which of the two you have chosen.</p>',
  'card': {'heading': 'Find out when one of them stops',
           'text': 'A machine that dies unattended should tell you, rather than wait until you '
                   'need it.',
           'tool': 'Healthchecks.io'}}]
