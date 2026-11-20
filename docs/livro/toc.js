// Populate the sidebar
//
// This is a script, and not included directly in the page, to control the total size of the book.
// The TOC contains an entry for each page, so if each page includes a copy of the TOC,
// the total size of the page becomes O(n**2).
class MDBookSidebarScrollbox extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        this.innerHTML = '<ol class="chapter"><li class="chapter-item expanded "><a href="index.html"><strong aria-hidden="true">1.</strong> Bem-vindo ao CGD</a></li><li class="chapter-item expanded "><a href="inicio.html"><strong aria-hidden="true">2.</strong> Comece aqui: instalar, escrever e executar</a></li><li class="chapter-item expanded "><a href="delegua-vs-cgd.html"><strong aria-hidden="true">3.</strong> Delégua original vs. CGD: o que muda e o que é novo</a></li><li class="chapter-item expanded "><a href="editor.html"><strong aria-hidden="true">4.</strong> Editor VS Code: cores, autocomplete e formatador</a></li><li class="chapter-item expanded "><a href="valores.html"><strong aria-hidden="true">5.</strong> Valores, tipos e variáveis</a></li><li class="chapter-item expanded "><a href="operadores.html"><strong aria-hidden="true">6.</strong> Operadores e ordem de avaliação</a></li><li class="chapter-item expanded "><a href="controle.html"><strong aria-hidden="true">7.</strong> Condições, escolha e laços</a></li><li class="chapter-item expanded "><a href="coletores.html"><strong aria-hidden="true">8.</strong> Laços como expressões</a></li><li class="chapter-item expanded "><a href="funcoes.html"><strong aria-hidden="true">9.</strong> Funções, assincronismo e rotinas paralelas</a></li><li class="chapter-item expanded "><a href="vetores.html"><strong aria-hidden="true">10.</strong> Vetores, compreensão e fatias</a></li><li class="chapter-item expanded "><a href="dicionarios.html"><strong aria-hidden="true">11.</strong> Dicionários, tuplas e clonagem</a></li><li class="chapter-item expanded "><a href="texto.html"><strong aria-hidden="true">12.</strong> Texto, Unicode e interpolação</a></li><li class="chapter-item expanded "><a href="classes.html"><strong aria-hidden="true">13.</strong> Classes, herança, mescla e estáticos</a></li><li class="chapter-item expanded "><a href="excecoes.html"><strong aria-hidden="true">14.</strong> Exceções e limpeza</a></li><li class="chapter-item expanded "><a href="modulos.html"><strong aria-hidden="true">15.</strong> Módulos estáticos e ~/.delegua/cgd</a></li><li class="chapter-item expanded "><a href="biblioteca.html"><strong aria-hidden="true">16.</strong> Funções nativas e entrada/saída</a></li><li class="chapter-item expanded "><a href="metadados.html"><strong aria-hidden="true">17.</strong> Decoradores e asserções</a></li><li class="chapter-item expanded "><a href="otimizacoes.html"><strong aria-hidden="true">18.</strong> Otimização (-o) e CTFE (@puro)</a></li><li class="chapter-item expanded "><a href="diagnosticos.html"><strong aria-hidden="true">19.</strong> Diagnósticos, códigos de erro e CLI</a></li><li class="chapter-item expanded "><a href="exclusoes.html"><strong aria-hidden="true">20.</strong> Exclusões de segurança</a></li><li class="chapter-item expanded "><a href="plataformas.html"><strong aria-hidden="true">21.</strong> Plataformas e toolchain C</a></li><li class="chapter-item expanded "><a href="bibliotecas-cgd.html"><strong aria-hidden="true">22.</strong> Bibliotecas cgd:* (Web, Dados, Cripto e Sistema)</a></li><li class="chapter-item expanded "><a href="metodos-estaticos.html"><strong aria-hidden="true">23.</strong> Membros estáticos (campos e métodos)</a></li><li class="chapter-item expanded "><a href="evolucao-04.html"><strong aria-hidden="true">24.</strong> Interfaces, classes abstratas, enums e FFI C</a></li><li class="chapter-item expanded "><a href="decisoes.html"><strong aria-hidden="true">25.</strong> Decisões de escopo: o que não vai entrar no CGD</a></li><li class="chapter-item expanded "><a href="runtime-erros.html"><strong aria-hidden="true">26.</strong> Lendo erros em tempo de execução (R0001)</a></li><li class="chapter-item expanded "><a href="stdlib-ampliada.html"><strong aria-hidden="true">27.</strong> Na prática: textos, estatística, caminhos e coleções</a></li><li class="chapter-item expanded affix "><li class="part-title">Guias técnicos aprofundados</li><li class="chapter-item expanded "><a href="desenvolvimento.html"><strong aria-hidden="true">28.</strong> Desenvolvimento</a></li><li class="chapter-item expanded "><a href="arquitetura.html"><strong aria-hidden="true">29.</strong> Arquitetura</a></li><li class="chapter-item expanded "><a href="compatibilidade.html"><strong aria-hidden="true">30.</strong> Compatibilidade</a></li><li class="chapter-item expanded "><a href="seguranca.html"><strong aria-hidden="true">31.</strong> Seguranca</a></li><li class="chapter-item expanded "><a href="ferramentas.html"><strong aria-hidden="true">32.</strong> Ferramentas</a></li><li class="chapter-item expanded "><a href="evolucao-linguagem.html"><strong aria-hidden="true">33.</strong> Evolucao linguagem</a></li><li class="chapter-item expanded "><a href="stdlib-sistema.html"><strong aria-hidden="true">34.</strong> Stdlib sistema</a></li><li class="chapter-item expanded "><a href="servidor-http.html"><strong aria-hidden="true">35.</strong> Servidor http</a></li><li class="chapter-item expanded "><a href="assincronismo.html"><strong aria-hidden="true">36.</strong> Assincronismo</a></li><li class="chapter-item expanded "><a href="rotinas.html"><strong aria-hidden="true">37.</strong> Rotinas</a></li></ol>';
        // Set the current, active page, and reveal it if it's hidden
        let current_page = document.location.href.toString().split("#")[0].split("?")[0];
        if (current_page.endsWith("/")) {
            current_page += "index.html";
        }
        var links = Array.prototype.slice.call(this.querySelectorAll("a"));
        var l = links.length;
        for (var i = 0; i < l; ++i) {
            var link = links[i];
            var href = link.getAttribute("href");
            if (href && !href.startsWith("#") && !/^(?:[a-z+]+:)?\/\//.test(href)) {
                link.href = path_to_root + href;
            }
            // The "index" page is supposed to alias the first chapter in the book.
            if (link.href === current_page || (i === 0 && path_to_root === "" && current_page.endsWith("/index.html"))) {
                link.classList.add("active");
                var parent = link.parentElement;
                if (parent && parent.classList.contains("chapter-item")) {
                    parent.classList.add("expanded");
                }
                while (parent) {
                    if (parent.tagName === "LI" && parent.previousElementSibling) {
                        if (parent.previousElementSibling.classList.contains("chapter-item")) {
                            parent.previousElementSibling.classList.add("expanded");
                        }
                    }
                    parent = parent.parentElement;
                }
            }
        }
        // Track and set sidebar scroll position
        this.addEventListener('click', function(e) {
            if (e.target.tagName === 'A') {
                sessionStorage.setItem('sidebar-scroll', this.scrollTop);
            }
        }, { passive: true });
        var sidebarScrollTop = sessionStorage.getItem('sidebar-scroll');
        sessionStorage.removeItem('sidebar-scroll');
        if (sidebarScrollTop) {
            // preserve sidebar scroll position when navigating via links within sidebar
            this.scrollTop = sidebarScrollTop;
        } else {
            // scroll sidebar to current active section when navigating via "next/previous chapter" buttons
            var activeSection = document.querySelector('#sidebar .active');
            if (activeSection) {
                activeSection.scrollIntoView({ block: 'center' });
            }
        }
        // Toggle buttons
        var sidebarAnchorToggles = document.querySelectorAll('#sidebar a.toggle');
        function toggleSection(ev) {
            ev.currentTarget.parentElement.classList.toggle('expanded');
        }
        Array.from(sidebarAnchorToggles).forEach(function (el) {
            el.addEventListener('click', toggleSection);
        });
    }
}
window.customElements.define("mdbook-sidebar-scrollbox", MDBookSidebarScrollbox);
