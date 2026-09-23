//
//  Taxonomy.swift
//  AIPapers
//
//  The fixed three-level category system: Area -> Topic -> Subtopic. The
//  model classifies a paper into a Topic and Subtopic; the Area is derived
//  deterministically, never asked of the model. The one-line hints are what
//  make a small local model pick sensibly instead of dumping everything into
//  the broadest label.
//

import Foundation

nonisolated enum Taxonomy {
    struct Subtopic: Sendable {
        let name: String
        let hint: String
    }

    struct Topic: Sendable {
        let name: String
        let area: String
        let hint: String
        let subtopics: [Subtopic]
    }

    /// Papers that fit none of the AI-engineering topics (classical stats/ML
    /// from the wider arXiv feed) — an honest bucket beats a forced wrong label.
    static let otherArea = "Other"
    static let uncategorized = "Uncategorized"
    /// Stored when a paper was classified but no listed subtopic fit — so it
    /// counts as done and is never re-sent to the model.
    static let otherSubtopic = "Other"
    static let unclassifiedSubtopic = "Unclassified"

    private static func sub(_ name: String, _ hint: String) -> Subtopic {
        Subtopic(name: name, hint: hint)
    }

    static let all: [Topic] = [
        Topic(name: "LLM", area: "Language & Agents", hint: "general language-model capabilities, architectures, prompting, alignment of language models; use only when no more specific topic fits", subtopics: [
            sub("Capabilities & Scaling", "emergent abilities, scaling laws, comparisons of language models"),
            sub("Alignment & Safety", "alignment, jailbreaks, hallucination, trustworthiness of language models"),
            sub("Architectures & Long Context", "new transformer variants, state-space models, tokenization, long context"),
            sub("Domain Applications", "language models applied to a specific field such as science, law, medicine or code"),
        ]),
        Topic(name: "Agents", area: "Language & Agents", hint: "autonomous or multi-agent systems, tool use, planning, agentic workflows, agent security", subtopics: [
            sub("Tool Use & Planning", "tool calling, planning, task decomposition"),
            sub("Multi-Agent Systems", "collaboration or competition between several agents"),
            sub("Agent Security", "prompt injection, hijacking, sandboxing, agent attacks and defenses"),
            sub("Memory & Frameworks", "agent memory, orchestration frameworks, harnesses"),
        ]),
        Topic(name: "Reasoning", area: "Language & Agents", hint: "chain-of-thought, math, logic and code reasoning, reinforcement learning for reasoning", subtopics: [
            sub("Math & Logic", "mathematical or logical problem solving"),
            sub("Code Reasoning", "reasoning about or generating programs"),
            sub("RL for Reasoning", "reinforcement learning, self-distillation or rewards to improve reasoning"),
            sub("Chain-of-Thought", "prompting or training intermediate reasoning steps"),
        ]),
        Topic(name: "Generative AI", area: "Language & Agents", hint: "diffusion and other generative models for images, video, audio or text", subtopics: [
            sub("Image & Video Generation", "generating or editing images and video"),
            sub("Audio & Speech", "speech, music and audio generation"),
            sub("Diffusion Methods", "diffusion or flow-based generative modeling techniques"),
        ]),
        Topic(name: "RAG", area: "Data & Retrieval", hint: "retrieval-augmented generation, grounding a model in external context", subtopics: [
            sub("Chunking & Indexing", "how documents are split, indexed and stored for retrieval"),
            sub("Grounding & Citation", "making answers faithful to and traceable to sources"),
            sub("Context Selection", "deciding which retrieved context to use or trust"),
        ]),
        Topic(name: "Retrieval", area: "Data & Retrieval", hint: "search, ranking, embeddings, recommendation, information retrieval", subtopics: [
            sub("Embeddings", "representation learning for retrieval and similarity"),
            sub("Ranking & Search", "ranking models, query understanding, search systems"),
            sub("Recommendation", "recommender systems and personalization"),
        ]),
        Topic(name: "Training", area: "Training & Optimization", hint: "pretraining, optimizers, learning theory, self-distillation, data curation", subtopics: [
            sub("Optimizers & Theory", "optimization algorithms, convergence, learning theory"),
            sub("Data & Curation", "training data selection, filtering, synthetic data"),
            sub("Pretraining", "large-scale pretraining recipes and objectives"),
            sub("Reinforcement Learning", "RL training methods and policy optimization"),
        ]),
        Topic(name: "Fine-tuning", area: "Training & Optimization", hint: "post-training adaptation: SFT, LoRA, preference optimization, RLHF", subtopics: [
            sub("Supervised & PEFT", "supervised fine-tuning, LoRA, adapters, parameter-efficient methods"),
            sub("Preference Optimization", "RLHF, DPO and other preference or reward based tuning"),
            sub("Domain Adaptation", "adapting a model to a specific domain or task"),
        ]),
        Topic(name: "Model Optimization", area: "Training & Optimization", hint: "quantization, pruning, distillation, sparsity, compression", subtopics: [
            sub("Quantization", "lower-precision weights or activations"),
            sub("Pruning & Sparsity", "removing weights, heads or layers; sparse models"),
            sub("Distillation & Compression", "teacher-student distillation, model compression"),
        ]),
        Topic(name: "Inference", area: "Systems & Ops", hint: "serving, decoding, speculative decoding, KV cache, latency, throughput", subtopics: [
            sub("Decoding & Sampling", "speculative decoding, parallel decoding, sampling strategies"),
            sub("Serving & Scheduling", "request scheduling, batching, serving stacks, latency and throughput"),
            sub("KV Cache & Memory", "cache management, memory efficiency during inference"),
        ]),
        Topic(name: "AI Systems", area: "Systems & Ops", hint: "software/hardware co-design, compilers, frameworks, system architecture", subtopics: [
            sub("Compilers & Kernels", "kernel design, compilers, operator optimization"),
            sub("Hardware Co-design", "accelerators, chips, hardware-aware design"),
            sub("Frameworks & Architecture", "ML frameworks and overall system design"),
        ]),
        Topic(name: "AI Infrastructure", area: "Systems & Ops", hint: "GPU clusters, distributed training infrastructure, large-scale data pipelines", subtopics: [
            sub("Distributed Training", "parallelism strategies and multi-node training"),
            sub("Data Pipelines", "large-scale data loading, storage and processing"),
            sub("Cluster & Cost", "scheduling, utilization, cost and energy of GPU clusters"),
        ]),
        Topic(name: "MLOps", area: "Systems & Ops", hint: "deployment, monitoring, pipelines, reproducibility, model lifecycle", subtopics: [
            sub("Deployment", "shipping and releasing models to production"),
            sub("Monitoring & Observability", "drift detection, logging, tracing, production monitoring"),
            sub("Reproducibility", "experiment tracking, reproducible pipelines and versioning"),
        ]),
        Topic(name: "Multimodal", area: "Perception", hint: "vision-language, audio-visual and other cross-modal models", subtopics: [
            sub("Vision-Language", "models that combine images or video with text"),
            sub("Audio-Visual", "combining sound with vision, speaker and speech-in-video tasks"),
            sub("Embodied & Robotics", "perception and action for robots and embodied agents"),
        ]),
        Topic(name: "Computer Vision", area: "Perception", hint: "image, video and 3D perception: detection, segmentation, localization, point clouds", subtopics: [
            sub("Detection & Segmentation", "object detection, segmentation, recognition in images"),
            sub("3D & Point Clouds", "3D reconstruction, LiDAR, depth, localization"),
            sub("Video Understanding", "action recognition, tracking and temporal reasoning in video"),
            sub("Domain Imaging", "medical, remote-sensing and other specialized imaging"),
        ]),
        Topic(name: "Evaluation", area: "Evaluation", hint: "benchmarks, metrics, evaluation methodology, robustness and safety testing", subtopics: [
            sub("Benchmarks", "new datasets and benchmark suites"),
            sub("Metrics & Methodology", "how to measure, statistical validity of evaluation"),
            sub("Robustness & Safety Testing", "stress tests, red teaming, failure analysis"),
        ]),
        Topic(name: "Classical ML", area: otherArea, hint: "statistics and classical machine learning: boosting, clustering, forecasting, causal inference, off-policy evaluation, theory", subtopics: [
            sub("Statistics & Inference", "estimation, hypothesis testing, sampling and inference theory"),
            sub("Time Series & Forecasting", "forecasting and sequential data"),
            sub("Optimization Theory", "convex or non-convex optimization theory"),
            sub("Causal & Off-policy", "causal inference, bandits, off-policy learning and evaluation"),
        ]),
    ]

    static let names: [String] = all.map(\.name)

    /// Areas in display order.
    static let areas: [String] = all.map(\.area).reduce(into: []) { result, area in
        if !result.contains(area) { result.append(area) }
    }

    static func topics(in area: String) -> [Topic] {
        all.filter { $0.area == area }
    }

    static func topic(named name: String) -> Topic? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func area(of topic: String) -> String {
        Self.topic(named: topic)?.area ?? uncategorized
    }

    /// A subtopic name canonicalized within its topic, or nil if it isn't on that topic's list.
    static func canonicalSubtopic(_ raw: String, in topic: String) -> String? {
        Self.topic(named: topic)?.subtopics.first { $0.name.caseInsensitiveCompare(raw) == .orderedSame }?.name
    }

    /// Prompt block: one "- Name: hint" line per topic.
    static var promptList: String {
        all.map { "- \($0.name): \($0.hint)" }.joined(separator: "\n")
    }

    /// Prompt block: every topic with its subtopics nested underneath.
    static var nestedPromptList: String {
        all.map { topic in
            "- \(topic.name): \(topic.hint)\n" + topic.subtopics.map { "    - \($0.name): \($0.hint)" }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func subtopicPromptList(for topic: Topic) -> String {
        topic.subtopics.map { "- \($0.name): \($0.hint)" }.joined(separator: "\n")
    }
}
