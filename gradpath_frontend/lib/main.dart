import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const GradPathApp());

class GradPathApp extends StatelessWidget {
  const GradPathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GradPath',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: GPColors.bg,
        useMaterial3: true,
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
      ),
      home: const LandingPage(),
    );
  }
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scrollController = ScrollController();
  bool _scrolled = false;

  final _featuresKey = GlobalKey();
  final _howKey = GlobalKey();
  final _honorsKey = GlobalKey();
  final _faqKey = GlobalKey();
  final _ctaKey = GlobalKey();

  final _emailControllerTop = TextEditingController();
  final _emailControllerBottom = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final shouldBeScrolled = _scrollController.offset > 40;
      if (shouldBeScrolled != _scrolled)
        setState(() => _scrolled = shouldBeScrolled);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _emailControllerTop.dispose();
    _emailControllerBottom.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                const SizedBox(height: 110),
                HeroSection(
                  emailController: _emailControllerTop,
                  onPrimaryCta: () => _scrollTo(_ctaKey),
                ),
                const SizedBox(height: 80),
                RevealOnScroll(
                  scrollController: _scrollController,
                  child: Section(
                    key: _featuresKey,
                    title: "Turn requirements into a real plan.",
                    subtitle:
                        "GradPath maps prerequisites, term availability, and your constraints into a term-by-term schedule — with clear reasons behind every recommendation.",
                    child: const FeaturesGrid(),
                  ),
                ),
                const SizedBox(height: 110),
                RevealOnScroll(
                  scrollController: _scrollController,
                  child: Section(
                    key: _howKey,
                    title: "How it works",
                    subtitle:
                        "Upload your audit. Confirm what we parsed. Get a plan that highlights bottlenecks, fixes, and what-if scenarios.",
                    child: const HowItWorksTimeline(),
                  ),
                ),
                const SizedBox(height: 110),
                RevealOnScroll(
                  scrollController: _scrollController,
                  child: Section(
                    key: _honorsKey,
                    title: "Made for honors and transfer paths.",
                    subtitle:
                        "Honors-only sections, thesis sequencing, substitutions, transfer mappings, and term-only offerings — handled without the guesswork.",
                    child: const HonorsSection(),
                  ),
                ),
                const SizedBox(height: 110),
                RevealOnScroll(
                  scrollController: _scrollController,
                  child: Section(
                    key: _faqKey,
                    title: "FAQ",
                    subtitle:
                        "The questions students ask before trusting a planner.",
                    child: const FAQSection(),
                  ),
                ),
                const SizedBox(height: 110),
                FinalCTA(
                  key: _ctaKey,
                  emailController: _emailControllerBottom,
                  onSubmit: () {
                    final email = _emailControllerBottom.text.trim();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          email.isEmpty
                              ? "Drop your email to get updates."
                              : "Got it — we’ll email you when GradPath is ready.",
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 70),
                const Footer(),
                const SizedBox(height: 30),
              ],
            ),
          ),
          Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: AdaptiveNavBar(
              scrolled: _scrolled,
              onFeatures: () => _scrollTo(_featuresKey),
              onHow: () => _scrollTo(_howKey),
              onHonors: () => _scrollTo(_honorsKey),
              onFAQ: () => _scrollTo(_faqKey),
              onJoin: () => _scrollTo(_ctaKey),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Styling constants ----------
class GPColors {
  static const bg = Color(0xFFF7F7FB);
  static const text = Color(0xFF0F172A);
  static const subtext = Color(0xFF475569);
  static const border = Color(0xFFE8E8EF);
  static const card = Colors.white;

  // Brand greens (slightly different feel from the reference site)
  static const green = Color(0xFF15803D);
  static const green2 = Color(0xFF22C55E);
  static const greenSoft = Color(0xFFEAFBF0);

  // Unique GradPath accent (adds identity)
  static const accentInk = Color(0xFF0B3B2A);
}

// ---------- Navbar (full-width -> centered glass panel on scroll) ----------
class AdaptiveNavBar extends StatelessWidget {
  const AdaptiveNavBar({
    super.key,
    required this.scrolled,
    required this.onFeatures,
    required this.onHow,
    required this.onHonors,
    required this.onFAQ,
    required this.onJoin,
  });

  final bool scrolled;
  final VoidCallback onFeatures;
  final VoidCallback onHow;
  final VoidCallback onHonors;
  final VoidCallback onFAQ;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final contentMaxWidth = width > 1200 ? 1100.0 : width * 0.94;
    final panelWidth = width > 1200 ? 980.0 : width * 0.92;

    // Full-width (top state)
    if (!scrolled) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _NavRow(
              onFeatures: onFeatures,
              onHow: onHow,
              onHonors: onHonors,
              onFAQ: onFAQ,
              onJoin: onJoin,
              compact: false,
            ),
          ),
        ),
      );
    }

    // Centered glass panel (scrolled state) — distinct from pill-only navbars
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: panelWidth,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
          color: Colors.white.withOpacity(0.50), // a touch more glass
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              // Inner glass rim / highlight
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.28), // highlight rim
                    Colors.white.withOpacity(0.10),
                  ],
                ),
              ),
              child: Padding(
                // This padding creates the "rim thickness"
                padding: const EdgeInsets.all(1.2),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withOpacity(0.18),
                  ),
                  child: _NavRow(
                    onFeatures: onFeatures,
                    onHow: onHow,
                    onHonors: onHonors,
                    onFAQ: onFAQ,
                    onJoin: onJoin,
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.onFeatures,
    required this.onHow,
    required this.onHonors,
    required this.onFAQ,
    required this.onJoin,
    required this.compact,
  });

  final VoidCallback onFeatures;
  final VoidCallback onHow;
  final VoidCallback onHonors;
  final VoidCallback onFAQ;
  final VoidCallback onJoin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 860;

    return Row(
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: GPColors.greenSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFB7F7D0)),
              ),
              child: const Icon(Icons.school, size: 18, color: GPColors.green),
            ),
            const SizedBox(width: 10),
            const Text(
              "GradPath",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: GPColors.text,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (isWide) ...[
          _NavLink("Features", onTap: onFeatures),
          _NavLink("How it works", onTap: onHow),
          _NavLink("Honors", onTap: onHonors),
          _NavLink("FAQ", onTap: onFAQ),
          const SizedBox(width: 10),
        ],
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: GPColors.green,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16), // less “pill”
            ),
          ),
          onPressed: onJoin,
          child: const Text("Request an invite"),
        ),
      ],
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withOpacity(0.30) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: GPColors.text,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Layout helpers ----------
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxW = width > 1200 ? 1100.0 : width * 0.92;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: GPColors.text,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: GPColors.subtext,
              ),
            ),
            const SizedBox(height: 34),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------- Hero ----------
class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    required this.emailController,
    required this.onPrimaryCta,
  });

  final TextEditingController emailController;
  final VoidCallback onPrimaryCta;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxW = width > 1200 ? 1100.0 : width * 0.92;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Padding(
          padding: const EdgeInsets.only(top: 84, bottom: 10),
          child: Column(
            children: [
              const Text(
                "Know your graduation date.\nPlan the fastest path there.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 58,
                  fontWeight: FontWeight.w900,
                  height: 1.03,
                  letterSpacing: -0.8,
                  color: GPColors.text,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Upload your degree audit and course catalog.\nGradPath builds a term-by-term schedule and flags what could delay you.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: GPColors.subtext,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),

              // Signature chips (distinct feel)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _Chip("Prereq bottlenecks detected"),
                  _Chip("Honors & transfer support"),
                  _Chip("Fall/Spring/Summer planning"),
                ],
              ),

              const SizedBox(height: 24),

              // CTA row: less “pill” + more product-like
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          hintText: "Enter your email for updates",
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: GPColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: GPColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: GPColors.green,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GPColors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: onPrimaryCta,
                      child: const Text("Request an invite"),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              const Text(
                "No spam. Just launch updates.",
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),

              const SizedBox(height: 38),

              // Product preview container (still placeholder)
              Container(
                height: 440,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: GPColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: GPColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: const InteractivePlannerPreview(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: GPColors.greenSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: GPColors.accentInk,
        ),
      ),
    );
  }
}

// ---------- Features grid + hover cards ----------
class FeaturesGrid extends StatelessWidget {
  const FeaturesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = const [
      _Feature(
        "Degree Audit Parsing",
        "Upload your audit and confirm what we extracted.",
      ),
      _Feature(
        "Bottleneck Detection",
        "Find prereq chains and term-only blockers early.",
      ),
      _Feature(
        "Optimized Semester Plan",
        "Generate a schedule that respects prereqs and availability.",
      ),
      _Feature(
        "Honors Rules",
        "Honors-only courses, substitutions, and thesis sequencing.",
      ),
      _Feature(
        "What-If Simulator",
        "See the impact of fewer credits, summer, or a missed course.",
      ),
      _Feature(
        "Advisor Export",
        "Download a clean plan you can bring to advising.",
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w > 980 ? 3 : (w > 640 ? 2 : 1);
        final itemW = (w - (cols - 1) * 18) / cols;

        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: items
              .map(
                (f) => SizedBox(
                  width: itemW,
                  child: HoverCard(feature: f),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _Feature {
  final String title;
  final String desc;
  const _Feature(this.title, this.desc);
}

class HoverCard extends StatefulWidget {
  const HoverCard({super.key, required this.feature});
  final _Feature feature;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: GPColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: GPColors.border),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ]
              : [],
        ),
        transform: _hover
            ? (Matrix4.identity()..translate(0.0, -4.0))
            : Matrix4.identity(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: GPColors.greenSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 18,
                color: GPColors.green,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.feature.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: GPColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.feature.desc,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: GPColors.subtext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- How it works timeline ----------
class HowItWorksTimeline extends StatelessWidget {
  const HowItWorksTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth > 920;

        if (!isWide) {
          return Column(
            children: const [
              _StepCard(
                n: 1,
                title: "Upload your audit",
                desc: "Add your degree audit + requirements (PDF/CSV).",
              ),
              SizedBox(height: 16),
              _StepCard(
                n: 2,
                title: "Confirm the match",
                desc:
                    "Review extracted courses, fix mismatches, lock constraints.",
              ),
              SizedBox(height: 16),
              _StepCard(
                n: 3,
                title: "Get your plan",
                desc:
                    "See your graduation forecast, bottlenecks, and a recommended schedule.",
              ),
            ],
          );
        }

        return SizedBox(
          height: 420,
          child: Stack(
            children: [
              Positioned(
                left: c.maxWidth / 2,
                top: 10,
                bottom: 10,
                child: Container(width: 2, color: GPColors.border),
              ),
              Positioned(
                left: 0,
                top: 30,
                width: c.maxWidth / 2 - 50,
                child: const _StepTextBlock(
                  alignRight: true,
                  title: "Upload your audit",
                  desc:
                      "Upload your degree audit and course catalog (or use the template).",
                ),
              ),
              Positioned(
                left: c.maxWidth / 2 - 18,
                top: 36,
                child: const _TimelineNode(n: 1),
              ),
              Positioned(
                left: c.maxWidth / 2 + 50,
                top: 165,
                width: c.maxWidth / 2 - 50,
                child: const _StepTextBlock(
                  alignRight: false,
                  title: "Confirm the match",
                  desc:
                      "We parse what we can. You confirm it fast so the plan stays correct.",
                ),
              ),
              Positioned(
                left: c.maxWidth / 2 - 18,
                top: 171,
                child: const _TimelineNode(n: 2),
              ),
              Positioned(
                left: 0,
                top: 300,
                width: c.maxWidth / 2 - 50,
                child: const _StepTextBlock(
                  alignRight: true,
                  title: "Get your plan",
                  desc:
                      "An optimized schedule plus bottlenecks, risks, and what-if scenarios.",
                ),
              ),
              Positioned(
                left: c.maxWidth / 2 - 18,
                top: 306,
                child: const _TimelineNode(n: 3),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.n});
  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [GPColors.green, GPColors.green2],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: Text(
          "$n",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _StepTextBlock extends StatelessWidget {
  const _StepTextBlock({
    required this.alignRight,
    required this.title,
    required this.desc,
  });

  final bool alignRight;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: GPColors.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          desc,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: GPColors.subtext,
          ),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.n, required this.title, required this.desc});
  final int n;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: GPColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: GPColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [GPColors.green, GPColors.green2],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              child: Text(
                "$n",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: GPColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: GPColors.subtext,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Honors section ----------
class HonorsSection extends StatelessWidget {
  const HonorsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth > 900;

        Expanded card(String title, String body) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: GPColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: GPColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: GPColors.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: GPColors.subtext,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 300,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBFCFD),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: GPColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: title == "Honors track"
                            ? const HonorsMiniPreview()
                            : const TransferMiniPreview(),
                      ),
                    ),
                  ],
                ),
              ),
            );

        if (!isWide) {
          return Column(
            children: [
              Row(
                children: [
                  card(
                    "Honors track",
                    "Track honors credits, honors-only courses, and thesis sequencing.",
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  card(
                    "Transfer mapping",
                    "Match transfer credits to equivalents and avoid repeated courses.",
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            card(
              "Honors track",
              "Track honors credits, honors-only courses, and thesis sequencing.",
            ),
            const SizedBox(width: 18),
            card(
              "Transfer mapping",
              "Match transfer credits to equivalents and avoid repeated courses.",
            ),
          ],
        );
      },
    );
  }
}

// ---------- FAQ ----------
class FAQSection extends StatelessWidget {
  const FAQSection({super.key});

  @override
  Widget build(BuildContext context) {
    const faqs = [
      (
        "How accurate is PDF parsing?",
        "We extract what we can, then you confirm it. The planner is designed to stay correct even when a PDF is messy.",
      ),
      (
        "Does this replace academic advising?",
        "No. It helps you show up to advising with a clear plan and the exact blockers to discuss.",
      ),
      (
        "What if my catalog year changes?",
        "GradPath supports catalog-year rule sets so your plan stays consistent.",
      ),
      (
        "Can transfer credits work?",
        "Yes. Transfer credits are treated as completed requirements once mapped to the equivalent course.",
      ),
      (
        "What if I can only take 12 credits?",
        "Cap credits in the simulator to see the earliest realistic graduation term.",
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: faqs
            .map(
              (f) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: GPColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: GPColors.border),
                ),
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      f.$1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: GPColors.text,
                      ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(
                        f.$2,
                        style: const TextStyle(
                          color: GPColors.subtext,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ---------- Final CTA ----------
class FinalCTA extends StatelessWidget {
  const FinalCTA({
    super.key,
    required this.emailController,
    required this.onSubmit,
  });

  final TextEditingController emailController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxW = width > 1200 ? 1100.0 : width * 0.92;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
          decoration: BoxDecoration(
            color: GPColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: GPColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              const Text(
                "Launching soon — want updates?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: GPColors.text,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Drop your email and we’ll send you early access when it opens.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: GPColors.subtext,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          hintText: "Enter your email",
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: GPColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: GPColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: GPColors.green,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GPColors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: onSubmit,
                      child: const Text("Get updates"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Footer ----------
class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text(
          "GradPath",
          style: TextStyle(fontWeight: FontWeight.w900, color: GPColors.text),
        ),
        SizedBox(height: 8),
        Text(
          "Graduation planning & risk optimization.",
          style: TextStyle(color: GPColors.subtext),
        ),
        SizedBox(height: 14),
        Text(
          "Terms of Service   ·   Privacy Policy",
          style: TextStyle(color: GPColors.subtext),
        ),
      ],
    );
  }
}

// ---------- Reveal on scroll ----------
class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({
    super.key,
    required this.child,
    required this.scrollController,
    this.offsetY = 18,
    this.threshold = 120,
    this.duration = const Duration(milliseconds: 520),
  });

  final Widget child;
  final ScrollController scrollController;
  final double offsetY;
  final double threshold;
  final Duration duration;

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll> {
  final _key = GlobalKey();
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_shown) return;

    final ctx = _key.currentContext;
    if (ctx == null) return;

    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final pos = box.localToGlobal(Offset.zero);
    final height = MediaQuery.of(context).size.height;

    if (pos.dy < height - widget.threshold) {
      setState(() => _shown = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: AnimatedOpacity(
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        opacity: _shown ? 1 : 0,
        child: AnimatedSlide(
          duration: widget.duration,
          curve: Curves.easeOutCubic,
          offset: _shown ? Offset.zero : Offset(0, widget.offsetY / 100),
          child: widget.child,
        ),
      ),
    );
  }
}

class InteractivePlannerPreview extends StatefulWidget {
  const InteractivePlannerPreview({super.key});

  @override
  State<InteractivePlannerPreview> createState() =>
      _InteractivePlannerPreviewState();
}

class _InteractivePlannerPreviewState extends State<InteractivePlannerPreview> {
  // Simple demo data: draggable courses across terms
  final Map<String, List<_Course>> _terms = {
    "Fall 2024": [
      _Course("CS 120", "Intro CS", Icons.code),
      _Course("MATH 130", "Calc I", Icons.functions),
      _Course("ENG 101", "Comp I", Icons.edit),
    ],
    "Spring 2025": [
      _Course("CS 220", "Data Struct", Icons.account_tree),
      _Course("MATH 131", "Calc II", Icons.calculate),
    ],
    "Summer 2025": [_Course("HIST 201", "World Hist", Icons.public)],
  };

  final Map<String, List<_Course>> _originalTerms = {
    "Fall 2024": [
      _Course("CS 120", "Intro CS", Icons.code),
      _Course("MATH 130", "Calc I", Icons.functions),
      _Course("ENG 101", "Comp I", Icons.edit),
    ],
    "Spring 2025": [
      _Course("CS 220", "Data Struct", Icons.account_tree),
      _Course("MATH 131", "Calc II", Icons.calculate),
    ],
    "Summer 2025": [_Course("HIST 201", "World Hist", Icons.public)],
  };

  String? _hoveredTerm;
  _Course? _dragging;
  String _earliestGradDate = "Spring 2026";
  bool _hasOptimization = false;

  void _moveCourse(_Course course, String from, String to) {
    if (from == to) return;
    setState(() {
      _terms[from]!.removeWhere((c) => c.id == course.id);
      _terms[to]!.add(course);

      // Check if CS 220 was moved to Fall
      if (course.code == "CS 220" && to == "Fall 2024") {
        _earliestGradDate = "Fall 2025";
        _hasOptimization = true;
      } else if (course.code == "CS 220" && to == "Spring 2025") {
        _earliestGradDate = "Spring 2026";
        _hasOptimization = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final isWide = c.maxWidth > 860;

        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top mini-header inside the preview
              Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: _Pill(
                      key: ValueKey(_earliestGradDate),
                      icon: Icons.auto_graph_rounded,
                      label: "Earliest grad: $_earliestGradDate",
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: _hasOptimization
                        ? _Pill(
                            key: const ValueKey("optimized"),
                            icon: Icons.check_circle,
                            label: "Path optimized!",
                            subtle: false,
                          )
                        : _Pill(
                            key: const ValueKey("bottleneck"),
                            icon: Icons.warning_amber_rounded,
                            label: "1 bottleneck detected",
                            subtle: true,
                          ),
                  ),
                  const Spacer(),
                  if (isWide)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: GPColors.greenSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: GPColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.drag_indicator,
                            size: 16,
                            color: GPColors.green,
                          ),
                          SizedBox(width: 6),
                          Text(
                            "Drag courses",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: GPColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // Board
              Expanded(
                child: isWide
                    ? Row(
                        children: _terms.keys
                            .map((t) => Expanded(child: _TermColumn(term: t)))
                            .toList()
                            .expand((w) sync* {
                          yield w;
                          if (w != _terms.keys.last)
                            yield const SizedBox(width: 14);
                        }).toList(),
                      )
                    : ListView(
                        children: _terms.keys
                            .map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _TermColumn(term: t),
                              ),
                            )
                            .toList(),
                      ),
              ),

              const SizedBox(height: 12),

              // Bottom hint / “explainability”
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: GPColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: GPColors.subtext,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _dragging == null
                            ? "Tip: drag “CS 220” earlier to see how it affects your path."
                            : "Drop “${_dragging!.code}” into a semester.",
                        style: const TextStyle(color: GPColors.subtext),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _TermColumn({required String term}) {
    final courses = _terms[term]!;
    final isHot = _hoveredTerm == term;

    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (payload) {
        setState(() => _hoveredTerm = term);
        return true;
      },
      onLeave: (_) => setState(() => _hoveredTerm = null),
      onAcceptWithDetails: (payload) {
        setState(() => _hoveredTerm = null);
        _moveCourse(payload.data.course, payload.data.fromTerm, term);
      },
      builder: (context, _, __) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isHot ? GPColors.greenSoft.withOpacity(0.55) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isHot ? GPColors.green.withOpacity(0.35) : GPColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Term header
              Row(
                children: [
                  Text(
                    term,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: GPColors.text,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: GPColors.border),
                    ),
                    child: Text(
                      "${courses.length} classes",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GPColors.subtext,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Courses
              Expanded(
                child: ListView.separated(
                  itemCount: courses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final course = courses[i];
                    return Draggable<_DragPayload>(
                      data: _DragPayload(course: course, fromTerm: term),
                      onDragStarted: () => setState(() => _dragging = course),
                      onDragEnd: (_) => setState(() => _dragging = null),
                      feedback: Material(
                        color: Colors.transparent,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 320,
                          ), // ✅ gives feedback a size
                          child: _CourseCard(course: course, dragging: true),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: _CourseCard(course: course),
                      ),
                      child: _CourseCard(course: course),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // Little “risk” chip to make it feel like GradPath, not Rem
              if (term == "Spring 2025" && !_hasOptimization)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lock_clock,
                        size: 18,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Prereq chain: CS 220 → CS 330 (Fall-only)",
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (term == "Fall 2024" && _hasOptimization)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: GPColors.green),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Optimized! Graduation moved to Fall 2025",
                          style: TextStyle(
                            color: GPColors.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ----- Small UI bits -----
class _Course {
  final String id;
  final String code;
  final String name;
  final IconData icon;

  _Course(this.code, this.name, this.icon) : id = "$code::$name";
}

class _DragPayload {
  final _Course course;
  final String fromTerm;
  const _DragPayload({required this.course, required this.fromTerm});
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, this.dragging = false});

  final _Course course;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            dragging ? Colors.white.withOpacity(0.95) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GPColors.border),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // ✅ important in overlays
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: GPColors.greenSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GPColors.border),
            ),
            child: Icon(course.icon, size: 18, color: GPColors.green),
          ),
          const SizedBox(width: 12),
          Flexible(
            // ✅ instead of Expanded
            fit: FlexFit.loose,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.code,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: GPColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  course.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GPColors.subtext,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.drag_handle, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.icon,
    required this.label,
    this.subtle = false,
  });

  final IconData icon;
  final String label;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: subtle ? const Color(0xFFF8FAFC) : GPColors.greenSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GPColors.border),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: subtle ? GPColors.subtext : GPColors.green,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: subtle ? GPColors.subtext : GPColors.green,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Mini previews for Honors + Transfer ----------
class HonorsMiniPreview extends StatefulWidget {
  const HonorsMiniPreview({super.key});

  @override
  State<HonorsMiniPreview> createState() => _HonorsMiniPreviewState();
}

class _HonorsMiniPreviewState extends State<HonorsMiniPreview> {
  int _activeStep = 1;

  @override
  Widget build(BuildContext context) {
    return _MiniFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniChip(
                icon: Icons.verified,
                label: "Honors credits: 18/24",
                tone: _MiniTone.green,
              ),
              _MiniChip(
                icon: Icons.timeline,
                label: "Thesis sequence",
                tone: _MiniTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Preview area takes remaining space
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: GPColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // spine
                  SizedBox(
                    width: 20,
                    child: Column(
                      children: List.generate(3, (i) {
                        final step = i + 1;
                        final active = step == _activeStep;
                        final done = step < _activeStep;

                        return Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: active || done
                                      ? GPColors.green
                                      : const Color(0xFFE2E8F0),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (step != 3)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    color: done
                                        ? GPColors.green.withOpacity(0.6)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // steps (scrollable)
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MiniStepRow(
                            dense: false,
                            title: "HONR 210: Methods",
                            subtitle: "Required before thesis",
                            active: _activeStep == 1,
                            onTap: () => setState(() => _activeStep = 1),
                          ),
                          const SizedBox(height: 8),
                          _MiniStepRow(
                            dense: false,
                            title: "HONR 350: Proposal",
                            subtitle: "Unlocked after Methods",
                            active: _activeStep == 2,
                            onTap: () => setState(() => _activeStep = 2),
                          ),
                          const SizedBox(height: 8),
                          _MiniStepRow(
                            dense: false,
                            title: "HONR 499: Thesis",
                            subtitle: "Spring-only section",
                            active: _activeStep == 3,
                            onTap: () => setState(() => _activeStep = 3),
                            warning: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            "Tap steps to preview the sequence.",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class TransferMiniPreview extends StatefulWidget {
  const TransferMiniPreview({super.key});

  @override
  State<TransferMiniPreview> createState() => _TransferMiniPreviewState();
}

class _TransferMiniPreviewState extends State<TransferMiniPreview> {
  final List<_TransferRow> _rows = [
    _TransferRow("MATH 1XX", "MATH 130 (Calc I)", true),
    _TransferRow("ENG 101", "ENG 101 (Comp I)", true),
    _TransferRow("CS 2XX", "CS 120 (Intro CS)", false),
  ];

  @override
  Widget build(BuildContext context) {
    return _MiniFrame(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                _MiniChip(
                  icon: Icons.swap_horiz,
                  label: "3 credits imported",
                  tone: _MiniTone.neutral,
                ),
                _MiniChip(
                  icon: Icons.link,
                  label: "Mappings",
                  tone: _MiniTone.green,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Preview area takes remaining space
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GPColors.border),
                ),
                child: Column(
                  children: [
                    // header
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Transfer",
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: const Color(0xFF334155),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Equivalent",
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: const Color(0xFF334155),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Status",
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: const Color(0xFF334155),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 6),

                    // ✅ constrained list area (no overflow)
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          return _TransferMiniRow(
                            row: r,
                            onTap: () => setState(
                              () => _rows[i] = r.copyWith(mapped: !r.mapped),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              "Tap a row to toggle mapping.",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferMiniRow extends StatelessWidget {
  const _TransferMiniRow({required this.row, required this.onTap});

  final _TransferRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:
              row.mapped ? GPColors.greenSoft.withOpacity(0.75) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                row.mapped ? GPColors.green.withOpacity(0.35) : GPColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                row.from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: GPColors.text,
                  fontSize: 12.5,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.to,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GPColors.subtext,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(mapped: row.mapped),
          ],
        ),
      ),
    );
  }
}

// ---------- Helpers ----------
class _MiniFrame extends StatelessWidget {
  const _MiniFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (_, constraints) {
          // If height is unbounded, don't force expand. Just return the child.
          final hasBoundedH = constraints.hasBoundedHeight;
          final hasBoundedW = constraints.hasBoundedWidth;

          if (!hasBoundedH || !hasBoundedW) {
            return child;
          }

          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: child,
          );
        },
      ),
    );
  }
}

enum _MiniTone { green, neutral }

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final _MiniTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = tone == _MiniTone.green
        ? GPColors.greenSoft.withOpacity(0.85)
        : Colors.white.withOpacity(0.9);
    final border = tone == _MiniTone.green
        ? GPColors.green.withOpacity(0.25)
        : GPColors.border;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 17,
            color: tone == _MiniTone.green ? GPColors.green : GPColors.subtext,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: tone == _MiniTone.green ? GPColors.text : GPColors.subtext,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStepRow extends StatelessWidget {
  const _MiniStepRow({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
    this.warning = false,
    this.dense = false,
  });

  final String title;
  final String subtitle;
  final bool active;
  final bool warning;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final padV = dense ? 7.0 : 14.0;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: padV),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? GPColors.border : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              warning ? Icons.warning_amber_rounded : Icons.check_circle,
              size: 18,
              color: warning ? const Color(0xFFF59E0B) : GPColors.green,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: GPColors.text,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GPColors.subtext,
                      fontSize: 12,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.mapped});
  final bool mapped;

  @override
  Widget build(BuildContext context) {
    final bg = mapped
        ? GPColors.green.withOpacity(0.10)
        : const Color(0xFF94A3B8).withOpacity(0.12);
    final fg = mapped ? GPColors.green : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.20)),
      ),
      child: Text(
        mapped ? "Mapped ✓" : "Review",
        style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 12),
      ),
    );
  }
}

class _TransferRow {
  final String from;
  final String to;
  final bool mapped;
  const _TransferRow(this.from, this.to, this.mapped);

  _TransferRow copyWith({bool? mapped}) =>
      _TransferRow(from, to, mapped ?? this.mapped);
}
