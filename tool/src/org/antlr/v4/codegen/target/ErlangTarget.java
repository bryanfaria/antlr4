/*
 * Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */

package org.antlr.v4.codegen.target;

import org.antlr.v4.codegen.CodeGenerator;
import org.antlr.v4.codegen.Target;
import org.antlr.v4.parse.ANTLRParser;
import org.antlr.v4.tool.Grammar;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public class ErlangTarget extends Target {
	protected static final HashSet<String> reservedWords = new HashSet<>(Arrays.asList(
		// Erlang reserved words (keywords)
		"after", "and", "andalso", "band", "begin", "bnot", "bor", "bsl", "bsr", "bxor",
		"case", "catch", "cond", "div", "end", "fun", "if", "let", "not", "of",
		"or", "orelse", "receive", "rem", "try", "when", "xor",

		// Erlang built-in atoms to escape
		"true", "false", "undefined", "error", "ok", "self", "throw", "exit",

		// Runtime conflicts - these would clash with generated code
		"state", "rule", "action", "start", "stop", "exception",

		// Common BIFs that might conflict
		"apply", "binary_to_list", "exit", "get", "halt", "hd", "length",
		"list_to_binary", "list_to_tuple", "make_ref", "node", "now",
		"put", "register", "round", "send", "size", "spawn", "tl", "trunc", "tuple_to_list",
		"unregister", "whereis",

		// Module attributes
		"module", "export", "import", "record", "include", "include_lib",
		"define", "ifdef", "ifndef", "else", "endif", "undef",

		// Common names that might clash
		"input", "token", "ctx", "context"
	));

	public ErlangTarget(CodeGenerator gen) {
		super(gen);
	}

	@Override
	protected Set<String> getReservedWords() {
		return reservedWords;
	}

	@Override
	public boolean isATNSerializedAsInts() {
		return true;
	}

	/**
	 * Convert a grammar name to Erlang snake_case module naming convention.
	 * For example: "MyGrammar" becomes "my_grammar"
	 */
	private String toSnakeCase(String name) {
		StringBuilder result = new StringBuilder();
		for (int i = 0; i < name.length(); i++) {
			char c = name.charAt(i);
			if (Character.isUpperCase(c)) {
				if (i > 0) {
					result.append('_');
				}
				result.append(Character.toLowerCase(c));
			} else {
				result.append(c);
			}
		}
		return result.toString();
	}

	@Override
	public String getRecognizerFileName(boolean header) {
		CodeGenerator gen = getCodeGenerator();
		Grammar g = gen.g;
		assert g != null;
		String name;
		switch (g.getType()) {
			case ANTLRParser.PARSER:
				name = g.name.endsWith("Parser") ? g.name.substring(0, g.name.length() - 6) : g.name;
				return toSnakeCase(name) + "_parser.erl";
			case ANTLRParser.LEXER:
				name = g.name.endsWith("Lexer") ? g.name.substring(0, g.name.length() - 5) : g.name;
				return toSnakeCase(name) + "_lexer.erl";
			case ANTLRParser.COMBINED:
				return toSnakeCase(g.name) + "_parser.erl";
			default:
				return "INVALID_FILE_NAME";
		}
	}

	/**
	 * A given grammar T, return the listener name such as
	 * t_listener.erl, if we're using the Erlang target.
	 */
	@Override
	public String getListenerFileName(boolean header) {
		CodeGenerator gen = getCodeGenerator();
		Grammar g = gen.g;
		assert g.name != null;
		return toSnakeCase(g.name) + "_listener.erl";
	}

	/**
	 * A given grammar T, return the visitor name such as
	 * t_visitor.erl, if we're using the Erlang target.
	 */
	@Override
	public String getVisitorFileName(boolean header) {
		CodeGenerator gen = getCodeGenerator();
		Grammar g = gen.g;
		assert g.name != null;
		return toSnakeCase(g.name) + "_visitor.erl";
	}

	/**
	 * A given grammar T, return a blank listener implementation
	 * such as t_base_listener.erl, if we're using the Erlang target.
	 */
	@Override
	public String getBaseListenerFileName(boolean header) {
		CodeGenerator gen = getCodeGenerator();
		Grammar g = gen.g;
		assert g.name != null;
		return toSnakeCase(g.name) + "_base_listener.erl";
	}

	/**
	 * A given grammar T, return a blank visitor implementation
	 * such as t_base_visitor.erl, if we're using the Erlang target.
	 */
	@Override
	public String getBaseVisitorFileName(boolean header) {
		CodeGenerator gen = getCodeGenerator();
		Grammar g = gen.g;
		assert g.name != null;
		return toSnakeCase(g.name) + "_base_visitor.erl";
	}
}
